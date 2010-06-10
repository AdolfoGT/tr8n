var Tr8n = Tr8n || {};

/****************************************************************************
**** Tr8n Translator
****************************************************************************/

Tr8n.Translator = Class.create({
  initialize: function() {
    var e = Prototype.emptyFunction;
    this.options = Object.extend({
    }, arguments[0] || { });

    this.translation_key_id = null;
    this.container = new Element('div', {id:'tr8n_translator', className: 'tr8n_translator', style: 'display:none;'});

    $(document.body).insert(this.container.observe('contextmenu', Event.stop));
    document.observe(Prototype.Browser.Opera ? 'click' : 'contextmenu', function(e){
      if (Prototype.Browser.Opera && !e.ctrlKey) {
        return;
      }

      // find the first element with translatable class
      // Safari has an issue with links, so we need a custom fix
      var translatable_node = Event.findElement(e, ".tr8n_translatable");
      var link_node = Event.findElement(e, "A");

      if (translatable_node == null) return;

      if (link_node) {
        var temp_href = link_node.href;
        link_node.href='javascript:void(0);';
        setTimeout(function() {link_node.href = temp_href;}, 500);
      }

      if (e.stop) e.stop();
      if (e.preventDefault) e.preventDefault();
      if (e.stopPropagation) e.stopPropagation();

      this.show(translatable_node);

    }.bind(this));
  },
  hide: function() {
    Effect.Fade(this.container, {duration: 0.25});
  },
  show: function(translatable_node) {
    tr8nLanguageSelector.hide();

    var html = "";
    if ($('tr8n_splash_screen')) {
      html += $("tr8n_splash_screen").innerHTML;
    } else {
      html += "<div style='font-size:18px;text-align:center; margin:5px; padding:10px; background-color:black;'>";
      html += "<img src='/tr8n/images/tr8n_logo.jpg' style='width:280px; vertical-align:middle;'>";
      html += "<img src='/tr8n/images/loading3.gif' style='width:200px; height:20px; vertical-align:middle;'>";
      html += "</div>"
    }
    $("tr8n_translator").innerHTML = html;

    var viewport_dimensions = document.viewport.getDimensions();
    var container_dimensions = this.container.getDimensions();
    var target_dimensions = Element.getDimensions(translatable_node);
    var target_position = Position.cumulativeOffset(translatable_node);
    var stem = {width:10, height:12};

    // default top left setting
    var container_position = {
      left: (target_position[0] + 'px'),
      top: (target_position[1] + target_dimensions.height + stem.height + 'px')
    }

    var stem = {v:"top", h:"left"};
    var stem_type = "top_left";
    var stem_offset = target_dimensions.width/2;
    var scroll_buffer = 100;
    var scroll_height = target_position[1] - scroll_buffer;

    // right calculations
    if (viewport_dimensions.width < target_position[0] + target_dimensions.width + viewport_dimensions.width/2) {
      container_position.left = target_position[0] + target_dimensions.width - container_dimensions.width + "px";
      stem_offset = target_dimensions.width/2;
      stem.h = "right";
    }

    window.scrollTo(target_position[0], scroll_height);
    this.container.setStyle(container_position);
    Effect.Appear(this.container, {duration: 0.25});

    this.translation_key_id = translatable_node.getAttribute('translation_key_id');
    var parameters = {translation_key_id: this.translation_key_id, stem_type:(stem.v + "_" + stem.h), stem_offset:stem_offset};

    window.setTimeout(function() {
      new Ajax.Request('/tr8n/language/translator', {
        parameters: parameters,
        method: 'get',
        evalScripts: true,
        onSuccess: function(transport) {
          var data = transport.responseText;
          new Effect.Fade('tr8n_translator', {
            duration: 0.2,
            afterFinish: function() {
              $('tr8n_translator').update(data);
              new Effect.Appear('tr8n_translator', {duration: 0.2});
            }
          })
        }
      });
    }, 500);
  },
  reportTranslation: function(key, translation_id) {
    var msg = "Reporting this translation will remove it from this list and the translator will be put on a watch list. \n\nAre you sure you want to report this translation?";
    if (!confirm(msg)) return;
    this.voteOnTranslation(key, translation_id, -1000);
  },
  voteOnTranslation: function(key, translation_id, vote) {
    $('tr8n_votes_for_' + translation_id).hide();
    $('tr8n_spinner_for_' + translation_id).show();

    // the long version updates and reorders translations - used in translator and phrase list
    // the short version only updates the total results - used everywhere else
    if ($('tr8n_translator_votes_for_' + key)) {
      new Ajax.Updater('tr8n_translator_votes_for_' + key, '/tr8n/translations/vote', {
        parameters: {
          translation_id: translation_id,
          vote: vote
        },
        method: 'post'
      });
    } else {
      new Ajax.Updater('tr8n_votes_for_' + translation_id, '/tr8n/translations/vote', {
        parameters: {
          translation_id: translation_id,
          vote: vote,
          short_version: true
        },
        method: 'post',
        onComplete: function() {
          $('tr8n_spinner_for_' + translation_id).hide();
          $('tr8n_votes_for_' + translation_id).show();
        }
      });
    }
  },
  insertDecorationToken: function (token) {
    var txtarea = document.getElementById('tr8n_translator_translation_label');
    this.wrapText(txtarea, "["+token+": ", "]");
  },
  insertToken: function (token) {
    this.insertAtCaret('tr8n_translator_translation_label', token);
  },
  wrapText: function (obj, beginTag, endTag) {
    if (typeof obj.selectionStart == 'number') {
        // Mozilla, Opera, and other browsers
        var start = obj.selectionStart;
        var end   = obj.selectionEnd;
        obj.value = obj.value.substring(0, start) + beginTag + obj.value.substring(start, end) + endTag + obj.value.substring(end, obj.value.length);

    } else if(document.selection) {
        // Internet Explorer
        obj.focus();
        var range = document.selection.createRange();
        if(range.parentElement() != obj)
          return false;

        if(typeof range.text == 'string')
          document.selection.createRange().text = beginTag + range.text + endTag;
    } else
        obj.value += text;

    return true;
  },
  insertAtCaret: function (areaId, text) {
    var txtarea = document.getElementById(areaId);
    var scrollPos = txtarea.scrollTop;
    var strPos = 0;
    var br = ((txtarea.selectionStart || txtarea.selectionStart == '0') ? "ff" : (document.selection ? "ie" : false ) );

    if (br == "ie") {
      txtarea.focus();
      var range = document.selection.createRange();
      range.moveStart ('character', -txtarea.value.length);
      strPos = range.text.length;
    } else if (br == "ff")
      strPos = txtarea.selectionStart;

    var front = (txtarea.value).substring(0, strPos);
    var back = (txtarea.value).substring(strPos, txtarea.value.length);
    txtarea.value=front+text+back;

    strPos = strPos + text.length;
    if (br == "ie") {
      txtarea.focus();
      var range = document.selection.createRange();
      range.moveStart ('character', -txtarea.value.length);
      range.moveStart ('character', strPos);
      range.moveEnd ('character', 0); range.select();
   }  else if (br == "ff") {
      txtarea.selectionStart = strPos;
      txtarea.selectionEnd = strPos;
      txtarea.focus();
    }
    txtarea.scrollTop = scrollPos;
  },
  switchTranslatorMode: function(translation_key_id, mode, source_url) {
    new Ajax.Updater('tr8n_translator_container', '/tr8n/language/translator', {
      parameters: {translation_key_id:translation_key_id, mode:mode, source_url:source_url},
      method: 'get',
      evalScripts: true
    });
  },
  submitTranslation: function() {
    if ($("tr8n_translator_translation_label").value.trim() == "") {
       return;
    }
    $('tr8n_translator_translation_container').hide();
    $('tr8n_translator_buttons_container').hide();
    $('tr8n_translator_spinner').show();
    $('tr8n_translator_form').submit();
  },
  submitViewingUserDependency: function() {
    $('tr8n_translator_translation_has_dependencies').value = "true";
    this.submitTranslation();
  },
  submitDependencies: function() {
    $('tr8n_translator_buttons_container').hide();
    $('tr8n_translator_dependencies_container').hide();
    $('tr8n_translator_spinner').show();
    $('tr8n_translator_form').submit();
  },
  translate: function(label, callback, opts) {
      opts = opts || {}
      new Ajax.Request('/tr8n/language/translate', {
        method: 'post',
        parameters: {
          label:       label,
          description: opts.description,
          tokens:      opts.tokens,
          options:     opts.options,
          language:    opts.language
        },
        onSuccess: function(request) {
          if (callback)
            callback(request.responseText);
        }
      });
  },
  translateBatch: function(phrases, callback) {
      new Ajax.Request('/tr8n/language/translate', {
        method: 'post',
        parameters: {phrases: phrases},
        onSuccess: function(request) {
          if (callback)
            callback(request.responseText);
        }
      });
  },
  suggestTranslation: function(translation_key_id, original, lang) {
      google.language.translate(original, "en", lang, function(result) {
          if (!result.error) {
              $("tr8n_translation_suggestion_" + translation_key_id).innerHTML = result.translation;
              $("tr8n_google_suggestion_container_" + translation_key_id).show();

              // for translator only
              if ($("tr8n_google_suggestion_section")) {
                  $("tr8n_google_suggestion_section").show();
              }
          }
      });
  }
});


/****************************************************************************
**** Tr8n Language Selector
****************************************************************************/

Tr8n.LanguageSelector = Class.create({
  initialize: function() {
    var e = Prototype.emptyFunction;
    this.options = Object.extend({
      zIndex: 10000
    }, arguments[0] || { });

    this.keyboardMode = false;
    this.loaded = false;

    this.container = new Element('div', {id:'tr8n_language_selector', className: 'tr8n_language_selector', style: 'display:none'});
    $(document.body).insert(this.container);
  },
  toggle: function() {
    ($("tr8n_language_selector").getStyle("display") == "none") ? this.show() : this.hide();
  },
  hide: function() {
    Effect.Fade(this.container, {duration: 0.25});
  },
  switchMode: function(mode) {
    new Ajax.Updater('tr8n_language_lists', '/tr8n/language/language_lists', {
      parameters: {mode:mode},
      method: 'get'
    });
  },
  removeLanguage: function(language_id) {
    new Ajax.Updater('tr8n_language_lists', '/tr8n/language/lists', {
      parameters: {language_action:'remove', language_id:language_id},
      method: 'post'
    });
  },
  show: function() {
    tr8nTranslator.hide();

    if (!this.loaded) {
      var html = "";
      if ($('tr8n_splash_screen')) {
        html += $("tr8n_splash_screen").innerHTML;
      } else {
        html += "<div style='font-size:18px;text-align:center; margin:5px; padding:10px; background-color:black;'>";
        html += "<img src='/tr8n/images/tr8n_logo.jpg' style='width:280px; vertical-align:middle;'>";
        html += "<img src='/tr8n/images/loading3.gif' style='width:200px; height:20px; vertical-align:middle;'>";
        html += "</div>"
      }
      $("tr8n_language_selector").innerHTML = html;
    }

    var trigger = $('tr8n_language_selector_trigger');

    var viewport_dimensions = document.viewport.getDimensions();
    var container_dimensions = this.container.getDimensions();
    var trigger_dimensions = Element.getDimensions(trigger);
    var trigger_position = Position.cumulativeOffset(trigger);

    // default top right settings
    var container_position = {
      left: trigger_position[0] + trigger_dimensions.width - container_dimensions.width + 'px',
      top: trigger_position[1] + trigger_dimensions.height + 4 + 'px',
      zIndex: 10000
    }

    // left calculations
    if (trigger_position[0] < viewport_dimensions.width / 2 ) {
      container_position.left = trigger_position[0] + 'px';
    }

    this.container.setStyle(container_position);
    Effect.Appear(this.container, {duration: 0.25});

    if (!this.loaded) {
      window.setTimeout(function() {
          new Ajax.Request('/tr8n/language/select', {
            method: 'get',
            evalScripts: true,
            onSuccess: function(transport) {
              var data = transport.responseText;
              new Effect.Fade('tr8n_language_selector', {
                duration: 0.2,
                afterFinish: function() {
                  $('tr8n_language_selector').update(data);
                  new Effect.Appear('tr8n_language_selector', {duration: 0.2});
                }
              })
            }
           })
      }, 100);
    }

    this.loaded = true;
  },
  enableInlineTranslations: function() {
    location = "/tr8n/language/switch?language_action=enable_inline_mode&source_url=" + location;
  },
  disableInlineTranslations: function() {
    location = "/tr8n/language/switch?language_action=disable_inline_mode&source_url=" + location;
  },
  toggleInlineTranslations: function() {
    location = "/tr8n/language/switch?language_action=toggle_inline_mode&source_url=" + location;
  },
  openTranslations: function() {
    location = "/tr8n/dashboard"
  },
  openSiteMap: function() {
    location = "/tr8n/translations/map"
  },
  openAwards: function() {
    location = "/tr8n/awards"
  },
  openMessageBoard: function() {
    location = "/tr8n/forum"
  },
  openLanguage: function() {
    location = "/tr8n/language"
  },
  openHelp: function() {
    location = "/tr8n/help"
  },
  toggleKeyboards: function() {
    if (!this.keyboardMode) {
      this.keyboardMode = true;

      var elements = document.getElementsByTagName("input");
      for(i=0; i<elements.length; i++) {
        if (elements[i].type == "text") VKI_attach(elements[i]);
      }
      elements = document.getElementsByTagName("textarea");
      for(i=0; i<elements.length; i++) {
        VKI_attach(elements[i]);
      }
    } else {
      location.reload();
    }
  }
})

/****************************************************************************
**** Tr8n Lightbox
****************************************************************************/

Tr8n.Lightbox = Class.create({
  initialize: function() {
    this.container = new Element('div', {id:'tr8n_lightbox', className: 'tr8n_lightbox', style: 'display:none'});
    $(document.body).insert(this.container);
    this.overlay = new Element('div', {id:'tr8n_lightbox_overlay', className: 'tr8n_black_overlay', style: 'display:none'});
    $(document.body).insert(this.overlay);
  },
  hide: function() {
    Effect.Fade(this.container, {duration: 0.25});
    this.overlay.setStyle("display:none");
  },
  show: function(url, opts) {
    tr8nTranslator.hide();
    tr8nLanguageSelector.hide();

    $("tr8n_lightbox").innerHTML = "<div style='font-size:18px;text-align:left;padding:10px;'><img src='/tr8n/images/indicator_white_large.gif' style='vertical-align:middle'> Loading...</div>";

    var viewport_dimensions = document.viewport.getDimensions();
    var overlay_height = viewport_dimensions.height < screen.availHeight ? screen.availHeight : viewport_dimensions.height;
    var overlay_width = viewport_dimensions.width < screen.availWidth ? screen.availWidth : viewport_dimensions.width;
    this.overlay.setStyle("top:0px; left:0px; display:inline; width:" + overlay_width + "px; height:" + overlay_height + "px;");

    opts = opts || {}
    opts["width"] = opts["width"] || (viewport_dimensions.width / 2);
    opts["height"] = opts["height"] || (viewport_dimensions.height / 2);
    opts["left"] = (document.body.scrollLeft + viewport_dimensions.width - opts["width"])/2;
    opts["top"] = (document.body.scrollTop + viewport_dimensions.height - opts["height"])/2 - 100;

    var style = "top:" + opts["top"] + "px;left:" + opts["left"] + "px;width:" + opts["width"] + "px;height:" + opts["height"] + "px;";
    this.container.setStyle(style);
    Effect.Appear(this.container, {duration: 0.25});

    new Ajax.Updater('tr8n_lightbox', url, {
      method: 'get',
      evalScripts: true
    });
  }
})


Tr8n.DomLoaded  = false
Event.observe(document,'dom:loaded',function(){Tr8n.DomLoaded = true;});


/****************************************************************************
**** Tr8n Initialization
****************************************************************************/

var tr8nTranslator = null;
var tr8nLanguageSelector = null;
var tr8nLightbox = null;

function initializeTr8n() {
  var setup = function() {
    tr8nTranslator = new Tr8n.Translator();
    tr8nLanguageSelector = new Tr8n.LanguageSelector();
    tr8nLightbox = new Tr8n.Lightbox();
  }
  if(Tr8n.DomLoaded) {
    setup()
  } else {
    Event.observe(document,'dom:loaded',setup);
  }
}


function initializeTr8nShortcuts() {
  shortcut.add("Ctrl+T",function() {
    tr8nLanguageSelector.toggleInlineTranslations();
  });

  shortcut.add("Ctrl+L",function() {
    tr8nLanguageSelector.toggle();
  });

  shortcut.add("Ctrl+K",function() {
    tr8nLanguageSelector.toggleKeyboards();
  });

  shortcut.add("Ctrl+Shift+T",function() {
    tr8nLanguageSelector.openTranslations();
  });

  shortcut.add("Ctrl+Shift+M",function() {
    tr8nLanguageSelector.openSiteMap();
  });

  shortcut.add("Ctrl+Shift+A",function() {
    tr8nLanguageSelector.openAwards();
  });

  shortcut.add("Ctrl+Shift+B",function() {
    tr8nLanguageSelector.openMessageBoard();
  });

  shortcut.add("Ctrl+Shift+L",function() {
    tr8nLanguageSelector.openLanguage();
  });

  shortcut.add("Ctrl+Shift+H",function() {
    tr8nLanguageSelector.openHelp();
  });
}

function initializeTr8nGoogleSuggestions() {
   google.load("language", "1");
}
