#--
# Copyright (c) 2010-2013 Michael Berkovich
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

class Tr8n::Admin::ApplicationsController < Tr8n::Admin::BaseController
  unloadable

  def index
    @apps = Tr8n::Application.filter(:params => params, :filter => Tr8n::ApplicationFilter)
  end
  
  def lb_update
    @app = Tr8n::Application.find_by_id(params[:app_id]) unless params[:app_id].blank?
    @app = Tr8n::Application.new unless @app
    
    render :layout => false
  end

  def update
    app = Tr8n::Application.find_by_id(params[:app][:id]) unless params[:app][:id].blank?
    
    if app
      app.update_attributes(params[:app])
    else
      app = Tr8n::Application.create(params[:app])
    end
    
    redirect_to_source
  end

  def delete
    params[:apps] = [params[:app_id]] if params[:app_id]
    if params[:apps]
      params[:apps].each do |app_id|
        app = Tr8n::Application.find_by_id(app_id)
        app.destroy if app
      end  
    end
    redirect_to_source
  end  

  def components
    @comps = Tr8n::Component.filter(:params => params, :filter => Tr8n::ComponentFilter)
  end

  def lb_update_component
    @comp = Tr8n::Component.find_by_id(params[:comp_id]) unless params[:comp_id].blank?
    @comp = Tr8n::Component.new unless @comp
    @apps = Tr8n::Application.options
    
    render :layout => false
  end

  def lb_add_sources_to_component
    @comp = Tr8n::Component.find_by_id(params[:comp_id])
    @sources = Tr8n::TranslationSource.find(:all, :order => "source asc")
    
    render :layout => false
  end

  def add_sources_to_component
    comp = Tr8n::Component.find(params[:comp_id])
    params[:source_ids].each do |src_id|
      src = Tr8n::TranslationSource.find(src_id)
      Tr8n::ComponentSource.find_or_create(comp, src)
    end

    redirect_to_source
  end

  def remove_sources_from_component
    params[:component_sources] = [params[:component_source_id]] if params[:component_source_id]
    if params[:component_sources]
      params[:component_sources].each do |csrc_id|
        csrc = Tr8n::ComponentSource.find_by_id(csrc_id)
        csrc.destroy if csrc
      end  
    end
    redirect_to_source
  end

  def update_component
    comp = Tr8n::Component.find_by_id(params[:comp][:id]) unless params[:comp][:id].blank?
    
    if comp
      comp.update_attributes(params[:comp])
    else
      comp = Tr8n::Component.create(params[:comp])
    end
    
    redirect_to_source
  end

  def component
    @comp = Tr8n::Component.find_by_id(params[:comp_id])

    unless @comp
      trfe("Invalid component id")
      return redirect_to_source
    end

    filter = {"wf_c0" => "component_id", "wf_o0" => "is", "wf_v0_0" => @comp.id}
    @sources = Tr8n::ComponentSource.filter(:params => params.merge(filter))
    @sources.wf_filter.extra_params.merge!({:comp_id => @comp.id})

    # klass = {
    #   :sources => Tr8n::TranslationKeySource,
    #   :locks => Tr8n::TranslationKeyLock,
    #   :comments => Tr8n::TranslationKeyComment,
    #   :translations => Tr8n::Translation,
    # }[params[:mode].to_sym] if params[:mode]
    # klass ||= Tr8n::Translation

    # filter = {"wf_c0" => "translation_key_id", "wf_o0" => "is", "wf_v0_0" => @key.id}
    # extra_params = {:key_id => @key.id, :mode => params[:mode]}
    # @results = klass.filter(:params => params.merge(filter))
    # @results.wf_filter.extra_params.merge!(extra_params)

  end

  def delete_component
    params[:comps] = [params[:comp_id]] if params[:comp_id]
    if params[:comps]
      params[:comps].each do |comp_id|
        comp = Tr8n::Component.find_by_id(comp_id)
        comp.destroy if comp
      end  
    end
    redirect_to_source
  end

  def domains
    @domains = Tr8n::TranslationDomain.filter(:params => params, :filter => Tr8n::TranslationDomainFilter)
  end

  def delete_domain
    params[:domains] = [params[:domain_id]] if params[:domain_id]
    if params[:domains]
      params[:domains].each do |domain_id|
        domain = Tr8n::TranslationDomain.find_by_id(domain_id)
        domain.destroy if domain
      end  
    end
    redirect_to_source
  end

  def sources
    @sources = Tr8n::TranslationSource.filter(:params => params, :filter => Tr8n::TranslationSourceFilter)
  end

  def source
    @source = Tr8n::TranslationSource.find_by_id(params[:source_id])

    unless @source
      trfe("Invalid source id")
      return redirect_to_source
    end

    filter = {"wf_c0" => "translation_source_id", "wf_o0" => "is", "wf_v0_0" => @source.id}
    @metrics = Tr8n::TranslationSourceMetric.filter(:params => params.merge(filter))
    @metrics.wf_filter.extra_params.merge!({:source_id => @source.id})
  end

  def recalculate_metric
    metric = Tr8n::TranslationSourceMetric.find_by_id(params[:metric_id])
    unless metric
      trfe("Invalid metric id")
      return redirect_to_source
    end

    metric.update_metrics!
    trfn("The metric has been updated")
    redirect_to_source
  end

  def recalculate_source
    source = Tr8n::TranslationSource.find_by_id(params[:source_id])
    unless source
      trfe("Invalid source id")
      return redirect_to_source
    end

    source.translation_source_metrics.each do |metric|
      metric.update_metrics!
    end

    trfn("All metrics have been updated")
    redirect_to_source
  end

  def lb_update_source
    @source = Tr8n::TranslationSource.find_by_id(params[:source_id]) unless params[:source_id].blank?
    @source = Tr8n::TranslationSource.new unless @source
    
    render :layout => false
  end

  def update_source
    source = Tr8n::TranslationSource.find_by_id(params[:source][:id]) unless params[:source][:id].blank?
    
    if source
      source.update_attributes(params[:source])
    else
      source = Tr8n::TranslationSource.create(params[:source])
    end
    
    redirect_to_source
  end
  
  def delete_source
    params[:sources] = [params[:source_id]] if params[:source_id]
    if params[:sources]
      params[:sources].each do |source_id|
        source = Tr8n::TranslationSource.find_by_id(source_id)
        source.destroy if source
      end  
    end
    redirect_to_source
  end

  def key_sources
    @key_sources = Tr8n::TranslationKeySource.filter(:params => params, :filter => Tr8n::TranslationKeySourceFilter)
  end

  def delete_key_source
    params[:key_sources] = [params[:key_source_id]] if params[:key_source_id]
    if params[:key_sources]
      params[:key_sources].each do |key_source_id|
        key_source = Tr8n::TranslationKeySource.find_by_id(key_source_id)
        key_source.destroy if key_source
      end  
    end
    redirect_to_source
  end

  def lb_caller
    @key_source = Tr8n::TranslationKeySource.find(params[:key_source_id])
    @caller = @key_source.details[params[:caller_key]]
    render :layout => false
  end  
end