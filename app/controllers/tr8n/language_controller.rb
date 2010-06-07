class Tr8n::LanguageController < Tr8n::BaseController

  before_filter :validate_current_translator, :except => [:select, :switch, :translate, :tr]
  before_filter :validate_language_management, :only => [:index]
  
  def translate
    return sanitize_api_response({"error" => "Api is disabled"}) unless Tr8n::Config.enable_api?
    return sanitize_api_response({"error" => "You must be logged in to use the api"}) if tr8n_current_user_is_guest?

    language = Tr8n::Language.for(params[:language]) || tr8n_current_language
    source = params[:source] || "API" 
    return sanitize_api_response(translate_phrase(language, params, {:source => source})) if params[:label]
    
    # API signature
    # {:source => "", :language => "", :phrases => [{:label => ""}]}
    
    # get all phrases for the specified source
    if params[:batch] == "true"
      if params[:sources].blank? and params[:source].blank?
        return sanitize_api_response({"error" => "No source/sources have been provided for the batch request."})
      end
      
      source_names = params[:sources] || [params[:source]]
      sources = Tr8n::TranslationSource.find(:all, :conditions => ["source in (?)", source_names])
      source_ids = sources.collect{|source| source.id}
      
      if source_ids.empty?
        conditions = ["1=2"]
      else
        conditions = ["(id in (select distinct(translation_key_id) from tr8n_translation_key_sources where translation_source_id in (?)))"]
        conditions << source_ids.uniq
      end
      
      translations = []
      Tr8n::TranslationKey.find(:all, :conditions => conditions).each_with_index do |tkey, index|
        trn = tkey.translate(language, {}, {:api => true})
        translations << trn 
      end
      
      return sanitize_api_response({:phrases => translations})
    elsif params[:phrases]
      phrases = []
      begin
        phrases = HashWithIndifferentAccess.new({:data => JSON.parse(params[:phrases])})[:data]
      rescue Exception => ex
        return sanitize_api_response({"error" => "Invalid request. JSON parsing failed: #{ex.message}"})
      end
      
      translations = []
      phrases.each do |phrase|
        phrase = {:label => phrase} if phrase.is_a?(String)
        translations << translate_phrase(language, phrase, {:source => source})
      end
      return sanitize_api_response({:phrases => translations})    
    end
    
    sanitize_api_response({"error" => "Invalid API request. Please read the documentation and try again."})
  rescue Tr8n::KeyRegistrationException => ex
    sanitize_api_response({"error" => ex.message})
  end
  alias :tr :translate
  
  def index
    @rules = tr8n_current_language.rules
    @fallback_language = (tr8n_current_language.fallback_language || tr8n_default_language)
  end
  
  def update_language_section
    @rules = tr8n_current_language.rules
    @fallback_language = (tr8n_current_language.fallback_language || tr8n_default_language)

    unless request.post?
      return render(:partial => params[:section], :locals => {:mode => params[:mode].to_sym})
    end
    
    @error_msg = validate_language
    if @error_msg
      return render(:partial => params[:section], :locals => {:mode => params[:mode].to_sym})
    end

    tr8n_current_language.update_attributes(params[:language])
    
    if params[:rules]
      old_rule_ids = tr8n_current_language.rules.collect{|rule| rule.id}
      parse_language_rules.each do |rule|
        rule.language = tr8n_current_language
        rule.save_with_log!(tr8n_current_translator)
        old_rule_ids.delete(rule.id)
      end

      # clean up the remaining/deleted rules
      old_rule_ids.each do |id| 
        rule = Tr8n::LanguageRule.find(id)
        rule.destroy_with_log!(tr8n_current_translator)
      end
    end
    
    tr8n_current_language.reload
    
    @rules = tr8n_current_language.rules
    @fallback_language = (tr8n_current_language.fallback_language || tr8n_default_language)

    render(:partial => params[:section], :locals => {:mode => :view})
  end
  
  # ajax method for updating language rules in edit mode
  def update_rules
    @rules = parse_language_rules
    
    unless params[:rule_action]
      return render(:partial => "rules")
    end
  
    if params[:rule_action].index("add_at")
      position = params[:rule_action].split("_").last.to_i
      @rules.insert(position, tr8n_current_language.default_rule)
    elsif params[:rule_action].index("delete_at")
      position = params[:rule_action].split("_").last.to_i
      @rules.delete_at(position)
    elsif params[:rule_action].index("clear_all")
      @rules = []
    end
    
    render :partial => "rules"      
  end
  
  # language selector window
  def select
    @inline_translations_allowed = false
    @inline_translations_enabled = false
    
    if tr8n_current_user_is_translator? 
      unless tr8n_current_translator.blocked?
        @inline_translations_allowed = true
        @inline_translations_enabled = tr8n_current_translator.enable_inline_translations?
      end
    else
      @inline_translations_allowed = Tr8n::Config.open_translator_mode?
    end
    
    @inline_translations_allowed = true if tr8n_current_user_is_admin?
    
    @source_url = request.env['HTTP_REFERER']
    @source_url.gsub!("locale", "previous_locale") if @source_url
    
    @all_languages = Tr8n::Language.enabled_languages
    @user_languages = Tr8n::LanguageUser.languages_for(tr8n_current_user) unless tr8n_current_user_is_guest?
    render :layout => false 
  end
  
  # language selector management functions
  def lists
    @mode = params[:mode] || "view"
    
    if request.post? 
      if params[:language_action] == "remove"
        lu = Tr8n::LanguageUser.find(:first, :conditions => ["language_id = ? and user_id = ?", params[:language_id], tr8n_current_user.id])
        lu.destroy
      end
      @mode = "edit"
    end
    
    @all_languages = Tr8n::Language.enabled_languages
    @user_languages = Tr8n::LanguageUser.languages_for(tr8n_current_user)
    render(:partial => "lists")  
  end
  
  def remove
    lu = Tr8n::LanguageUser.find(:first, :conditions => ["language_id = ? and user_id = ?", params[:language_id], tr8n_current_user.id])
    lu.destroy if lu
    redirect_to_source
  end
  
  # language selector processor
  def switch
    language_action = params[:language_action]
    
    return redirect_to_source if tr8n_current_user_is_guest?
    
    if tr8n_current_user_is_translator? # translator mode
      if language_action == "toggle_inline_mode"
        if tr8n_current_translator.enable_inline_translations?
          language_action = "disable_inline_mode"
        else      
          language_action = "enable_inline_mode"
        end
      end
      
      if language_action == "enable_inline_mode"
        tr8n_current_translator.enable_inline_translations!
      elsif language_action == "disable_inline_mode"
        tr8n_current_translator.disable_inline_translations!
      elsif language_action == "switch_language"
        tr8n_current_translator.switched_language!(Tr8n::Language.find_by_locale(params[:locale]))
      end   
    elsif language_action == "switch_language"  # non-translator mode
      Tr8n::LanguageUser.create_or_touch(tr8n_current_user, Tr8n::Language.find_by_locale(params[:locale]))
    elsif language_action == "become_translator" # non-translator mode
      Tr8n::Translator.register
    elsif language_action == "enable_inline_mode" or language_action == "toggle_inline_mode" # non-translator mode
      Tr8n::Translator.register.enable_inline_translations!
    end
    
    redirect_to_source
  end

  # inline translator popup window as well as translation backend method
  def translator
    @translation_key = Tr8n::TranslationKey.find(params[:translation_key_id])
    @translations = @translation_key.inline_translations_for(tr8n_current_language)
    @source_url = params[:source_url] || request.env['HTTP_REFERER']
    @translation = Tr8n::Translation.default_translation(@translation_key, tr8n_current_language, tr8n_current_translator)
    
    if params[:mode]  # switching modes
      @mode = params[:mode]
      return render(:partial => "translator_#{@mode}")
    else 
      @mode = (@translations.empty? ? "submit" : "votes") unless @mode
    end

    render(:layout => false)
  end
    
private

  # parse with safety - we don't want to disconnect existing translations from those rules
  def parse_language_rules
    rulz = []
    return rulz unless params[:rules]
    
    index = 0  
    while params[:rules]["#{index}"]
      rule_params = params[:rules]["#{index}"]
      rule_definition = params[:rules]["#{index}"][:definition]
      
      if rule_params.delete(:reset_values) == "true"
        rule_definition = {}
      end

      rule_class = rule_params[:type]
      rule_id = rule_params[:id]
      
      if rule_id.blank?
        rulz << rule_class.constantize.new(:definition => rule_definition)
      else
        rule = rule_class.constantize.find_by_id(rule_id)
        rule = rule_class.constantize.new unless rule
        rule.definition = rule_definition
        rulz << rule
      end
      index += 1
    end
    
    rulz
  end

  def translate_phrase(language, phrase, opts = {})
    return "" if phrase[:label].strip.blank?
    language.translate(phrase[:label], phrase[:description], {}, {:api => true, :source => opts[:source]})
  end
  
  def sanitize_api_response(response)
    if Tr8n::Config.api[:response_encoding] == "xml"
      render(:text => response.to_xml)
    else
      render(:text => response.to_json)
    end      
  end
end