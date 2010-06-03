require 'digest/md5'

class Tr8n::TranslationKey < ActiveRecord::Base
  set_table_name :tr8n_translation_keys
  establish_connection(Tr8n::Config.database) if Tr8n::Config.use_remote_database?
  
  has_many :translations,             :class_name => "Tr8n::Translation",           :dependent => :destroy
  has_many :translation_key_locks,    :class_name => "Tr8n::TranslationKeyLock",    :dependent => :destroy
  has_many :translation_key_sources,  :class_name => "Tr8n::TranslationKeySource",  :dependent => :destroy
  has_many :translation_sources,      :class_name => "Tr8n::TranslationSource",     :through => :translation_key_sources
  
  alias :locks :translation_key_locks
  alias :sources :translation_sources
  
  def self.find_or_create(label, desc = "", options = {})
    key = generate_key(label, desc)
    
    # translation keys don't ever change, so no real reason to invalidate them  
    tkey = Tr8n::Cache.fetch("translation_key_#{key}") do 
      existing_key = find_by_key(key) 
      
      unless existing_key
        if options[:api] and (not Tr8n::Config.api[:allow_key_registration])
          raise Tr8n::KeyRegistrationException.new("Key registration through API is disabled!")  
        end
      end

      existing_key || create(:key => key, :label => label, :description => desc)
    end
    
    # we should disable this in production  
    if options[:source] and Tr8n::Config.enabled_key_source_tracking?
      Tr8n::TranslationKeySource.find_or_create(tkey, Tr8n::TranslationSource.find_or_create(options[:source]))
    end
    
    tkey  
  end
  
  def self.generate_key(label, desc="")
    key = "#{label};;;#{desc}"
    Digest::MD5.hexdigest(key)
  end
  
  def tokenized_label
    @tokenized_label ||= Tr8n::TokenizedLabel.new(label)
  end
  
  delegate :tokens, :tokens?, :hidden_tokens, :hidden_tokens?, :sanitized_tokens, :sanitized_tokens?, :to => :tokenized_label
  delegate :sanitized_label, :tokenless_label, :words, :to => :tokenized_label

  # returns only the tokens that depend on one or more rules of the language, if any defined for the language
  def language_rules_dependant_tokens(language = Tr8n::Config.current_language)
    toks = []
    sanitized_tokens.each do |token|
      sanitized_token = Tr8n::TokenizedLabel.strip_token(token)
      
      # if token is of a form {object.method_name}
      sanitized_token = sanitized_token.split(".").first if sanitized_token.index(".")

      language.rule_classes.each do |lrc|
        toks << sanitized_token if lrc.dependant?(sanitized_token)
      end
    end

    toks << Tr8n::Config.viewing_user_token
    toks.uniq
  end

  def glossary
    @glossary ||= Tr8n::Glossary.find(:all, :conditions => ["keyword in (?)", words], :order => "keyword asc")
  end
  
  def glossary?
    not glossary.empty?
  end
  
  def lock_for(language)
    Tr8n::TranslationKeyLock.for(self, language)
  end
  
  def lock!(language = Tr8n::Config.current_language, translator = Tr8n::Config.current_translator)
    lock_for(language).lock!(translator)
  end

  def unlock!(language = Tr8n::Config.current_language, translator = Tr8n::Config.current_translator)
    lock_for(language).unlock!(translator)
  end
  
  def locked?(language = Tr8n::Config.current_language)
    lock_for(language).locked?
  end

  def unlocked?(language = Tr8n::Config.current_language)
    not locked?(language)
  end
    
  def add_translation(label, rules = nil, language = Tr8n::Config.current_language, translator = Tr8n::Config.current_translator)
    raise Tr8n::Exception.new("The sentence contains dirty words") unless language.clean_sentence?(label)
    
    translation = Tr8n::Translation.create(:translation_key => self, :language => language, 
                                           :translator => translator, :label => label, :rules => rules)
    translation.vote!(translator, 1)
    translation
  end

  # returns all translations for the key, language and minimal rank
  def translations_for(language, rank = nil)
    conditions = ["translation_key_id = ? and language_id = ?", self.id, language.id]
    
    if rank
      conditions[0] << " and rank >= ?"
      conditions << rank
    end

    Tr8n::Translation.find(:all, :conditions => conditions, :order => "rank desc")
  end

  # used by the inline popup dialog, we don't want to show blocked translations
  def inline_translations_for(language)
    translations_for(language, -50)
  end
  
  # returns only the translations that meet the minimum rank
  def valid_translations_for(language)
    Tr8n::Cache.fetch("translations_#{language.locale}_#{self.key}") do
      translations_for(language, Tr8n::Config.translation_threshold)
    end
  end
  
  def translation_with_such_rules_exist?(language_translations, translator, rules_hash)
    language_translations.each do |translation|
      return true if translation.translator == translator and translation.matches_rule_definitions?(rules_hash)
    end
    false
  end
  
  def generate_rule_permutations(language, translator, dependencies)
    return if dependencies.blank?
    
    token_rules = {}
    
    dependencies.each do |token, rule_types|
      rule_types.keys.each do |rule_type|
        rules = language.default_rules_for(rule_type)
        token_rules[token] = [] unless token_rules[token]
        token_rules[token] << rules
        token_rules[token].flatten!
      end
    end
    
    language_translations = translations_for(language)
    
    token_rules.combinations.each do |combination|
      rules = []
      rules_hash = {}
      combination.each do |token, language_rule|
        rules_hash[token] = language_rule.id.to_s
        rules << {:token => token, :rule_id => language_rule.id.to_s}
      end
      
      # if the user has previously create this particular combination, move on...
      next if translation_with_such_rules_exist?(language_translations, translator, rules_hash)

      translation = Tr8n::Translation.create(:translation_key => self, :language => language, :translator => translator, :label => sanitized_label, :rules => rules)
    end
  end

  def self.random
    find(:first, :offset => rand(count - 1))
  end

  # returns back grouped by context
  def find_all_valid_translations(translations)
    if translations.empty?
      return {:key => self.key, :label => self.label}
    end
    
    # if the first translation does not depend on any of the context rules
    # use it... we don't care about the rest of the rules.
    if translations.first.rules_hash.blank?
      return {:key => self.key, :label => translations.first.label}
    end
    
    # build a context hash for every kind of context rules combinations
    # only the first one in the list should be used
    context_hash_matches = {}
    valid_translations = []
    translations.each do |translation|
      context_key = translation.rules_hash || ""
      next if context_hash_matches[context_key]
      context_hash_matches[context_key] = true
      if translation.rules_definitions
        valid_translations << {:label => translation.label, :context => translation.rules_definitions.clone}
      else
        valid_translations << {:label => translation.label}
      end
    end

    # always add the default one at the end, so if none of the rules matched, use the english one
    valid_translations << {:label => self.label} unless context_hash_matches[""]
    {:key => self.key, :labels => valid_translations}
  end

  def find_first_valid_translation(translations, token_values)
    translations.each do |translation|
      return translation if translation.matches_rules?(token_values)
    end
    nil
  end
  
  def translate(language = Tr8n::Config.current_language, token_values = {}, options = {})
    return find_all_valid_translations(valid_translations_for(language)) if options[:api]
    
    if Tr8n::Config.disabled? or language.default?
      return substitute_tokens(label, token_values, options.merge(:fallback => false))
    end
    
    translation = find_first_valid_translation(valid_translations_for(language), token_values)
    
    # if the language has a fallback language, use it
    unless translation
      # we don't want to always go back to english... just process the current translation
      if language.fallback_language and not language.fallback_language.default?
        return translate(language.fallback_language, token_values, options.merge(:fallback => true))
      end
    end
    
    if options[:default_label] 
      options.merge!(:fallback => false)
      return decorate_translation(language, label, translation != nil, options)
    end
    
    if translation
      translated_label = translation.translate(token_values, options)
      return decorate_translation(language, translated_label, translation != nil, options)
    end
    
    options.merge!(:fallback => false)
    translated_label = substitute_tokens(label, token_values, options)
    decorate_translation(language, translated_label, translation != nil, options)  
  end

  # this is done when the translations engine is disabled
  def self.substitute_tokens(label, tokens, options = {})
    Tr8n::TranslationKey.new(:label => label).substitute_tokens(label, tokens, options)
  end

  def handle_default_lambda(lambda_token_name, lambda_token_value, token_values)
    return "{invalid lambda token}" unless Tr8n::Config.default_lambdas[lambda_token_name.to_s]
    
    # make sure that only the lambdas from the original label can be used in the translated label
    allowed_tokens = tokenized_label.lambda_tokens.collect{|lt| Tr8n::TokenizedLabel.parse_lambda_token(lt).first}
    return lambda_token_value unless allowed_tokens.include?(lambda_token_name)

    lambda_value = Tr8n::Config.default_lambdas[lambda_token_name.to_s].clone
    
    params = [lambda_token_value]
    params += token_values[lambda_token_name] if token_values[lambda_token_name]
    
    params.each_with_index do |param, index|
      lambda_value.gsub!("{$#{index}}", param.to_s)
    end
    
    lambda_value
  end
  
  def substitute_tokens(label, token_values, options = {})
    translated_label = label.clone
    
    # substitute basic tokens
    tokens.each do |token|
      translated_label.gsub!(token, token_value(token, token_values, options)) 
    end

    # substitute lambda tokens
    tokenized_label.lambda_tokens(translated_label).each do |token|
      lambda_token_name, lambda_token_value = Tr8n::TokenizedLabel.parse_lambda_token(token)
      next if lambda_token_name.blank?
      
      # lambda token provided
      if token_values[lambda_token_name] 
        
        # evaluate lambda proc
        if token_values[lambda_token_name].is_a?(Proc)
          lambda_value = token_values[lambda_token_name].call(lambda_token_value)
        
        # evaluate default lambda with params
        elsif token_values[lambda_token_name].is_a?(Array)
          lambda_value = handle_default_lambda(lambda_token_name, lambda_token_value, token_values)

        else
          lambda_value = token_values[lambda_token_name].to_s.gsub("{$0}", lambda_token_value)
          
        end  
      elsif Tr8n::Config.default_lambdas[lambda_token_name.to_s]
        lambda_value = handle_default_lambda(lambda_token_name, lambda_token_value, token_values)
        
      else  
        lambda_value = "{invalid lambda token}"
      end
      
      translated_label.gsub!(token, lambda_value) 
    end
    
    translated_label
  end

  def sanitize_token_value(value, options = {})
    return value.to_s unless options[:sanitize_values]
    ERB::Util.html_escape(value.to_s)
  end

  def token_value(token, token_values, options = {})
    stripped_token = Tr8n::TokenizedLabel.strip_token(token)
    
    # token is an object method call
    if stripped_token.index(".")  # object based token
      obj_name, method_name = stripped_token.split(".")
      
      obj = token_values[obj_name.to_sym]
      return "{missing token value}" unless obj
      
      return sanitize_token_value(obj.send(method_name))
    end
      
    value = token_values[stripped_token.to_sym]
    return "{missing token value}" unless value
    
    # token is an array
    if value.is_a?(Array)
      # if you provided an array, it better have some values
      return "{invalid array token value}" if value.empty?
      
      # if single object in the array return string value of the object
      return sanitize_token_value(value.first) if value.size == 1
      
      params = value[2..-1]
      params_with_object = [value.first] + params

      # if second param is symbol, invoke the method on the object with the remaining values
      return sanitize_token_value(value.first.send(value.second, *params)) if value.second.is_a?(Symbol) 

      # if second param is lambda, call lambda with the remaining values
      return sanitize_token_value(value.second.call(*params_with_object)) if value.second.is_a?(Proc)
      
      # if the second param is a string, substitute all of the numeric params,  
      # with the original object and all the following params
      if value.second.is_a?(String)
        parametrized_value = value.second.clone
        params_with_object.each_with_index do |val, i|
          parametrized_value.gsub!("{$#{i}}", sanitize_token_value(val))  
        end
        return parametrized_value
      end
      
      return "{invalid second token value}"
    end

    # simple token
    sanitize_token_value(value)
  end
  
  def decorate_translation(language, translated_label, translated = true, options = {})
    return translated_label if options[:skip_decorations]
    return translated_label if Tr8n::Config.current_user_is_guest?
    return translated_label unless Tr8n::Config.current_user_is_translator?
    return translated_label unless Tr8n::Config.current_translator.enable_inline_translations?
      
    return translated_label if locked?(language)

    classes = ['tr8n_translatable']
    
    if language.default?
      classes << 'tr8n_not_translated'
    elsif options[:fallback] 
      classes << 'tr8n_fallback'
    else
      classes << (translated ? 'tr8n_translated' : 'tr8n_not_translated')
    end  

    html = "<span class='#{classes.join(' ')}' translation_key_id='#{id}'>"
    html << translated_label
    html << "</span>"
    html
  end
      
  def after_save
    Tr8n::Cache.delete("translation_key_#{key}")
  end

  ###############################################################
  ## Search Related Stuff
  ###############################################################
  
  def self.search_phrase_type_options
    [["all phrases", "any"], 
     ["phrases without translations", "without"], 
     ["phrases with translations", "with"]] 
  end
  
  def self.search_phrase_status_options
     [["anything", "any"],
      ["pending approval", "pending"], 
      ["approved", "approved"]]
  end
  
  def self.search_conditions_for(params)
    conditions = [""]
    
    unless params[:search].blank?
      conditions[0] << "(tr8n_translation_keys.label like ? or tr8n_translation_keys.description like ?)" 
      conditions << "%#{params[:search]}%"
      conditions << "%#{params[:search]}%"  
    end

    # for with and approved, allow user to specify the kinds
    if params[:phrase_type] == "with"
      conditions[0] << " and " unless conditions[0].blank?
      conditions[0] << "tr8n_translation_keys.id in (select tr8n_translations.translation_key_id from tr8n_translations where tr8n_translations.language_id = ?) "
      conditions << Tr8n::Config.current_language.id
      
      # if approved, ensure that translation key is locked
      if params[:phrase_status] == "approved" 
        conditions[0] << " and " unless conditions[0].blank?
        conditions[0] << "tr8n_translation_keys.id in (select tr8n_translation_key_locks.translation_key_id from tr8n_translation_key_locks where tr8n_translation_key_locks.language_id = ? and tr8n_translation_key_locks.locked = ?) "
        conditions << Tr8n::Config.current_language.id
        conditions << true
      
        # if approved, ensure that translation key does not have a lock or unlocked
      elsif params[:phrase_status] == "pending" 
        conditions[0] << " and " unless conditions[0].blank?
        conditions[0] << "tr8n_translation_keys.id not in (select tr8n_translation_key_locks.translation_key_id from tr8n_translation_key_locks where tr8n_translation_key_locks.language_id = ? and tr8n_translation_key_locks.locked = ?) "
        conditions << Tr8n::Config.current_language.id
        conditions << true
      end
            
    elsif params[:phrase_type] == "without"
      conditions[0] << " and " unless conditions[0].blank?
      conditions[0] << "tr8n_translation_keys.id not in (select tr8n_translations.translation_key_id from tr8n_translations where tr8n_translations.language_id = ?)"
      conditions << Tr8n::Config.current_language.id
    end
    
    conditions
  end    
end
