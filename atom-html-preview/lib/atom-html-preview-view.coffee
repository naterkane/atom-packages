fs                    = require 'fs'
{CompositeDisposable, Disposable} = require 'atom'
{$, $$$, ScrollView}  = require 'atom-space-pen-views'
path                  = require 'path'
os                    = require 'os'

module.exports =
class AtomHtmlPreviewView extends ScrollView
  atom.deserializers.add(this)

  editorSub           : null
  onDidChangeTitle    : -> new Disposable()
  onDidChangeModified : -> new Disposable()

  @deserialize: (state) ->
    new AtomHtmlPreviewView(state)

  @content: ->
    @div class: 'atom-html-preview native-key-bindings', tabindex: -1, =>
      style = 'z-index: 2; padding: 2em;'
      @div class: 'show-error', style: style
      @div class: 'show-loading', style: style, "Loading HTML"

  constructor: ({@editorId, filePath}) ->
    super

    if @editorId?
      @resolveEditor(@editorId)
      @tmpPath = @getPath() # after resolveEditor
    else
      if atom.workspace?
        @subscribeToFilePath(filePath)
      else
        # @subscribe atom.packages.once 'activated', =>
        atom.packages.onDidActivatePackage =>
          @subscribeToFilePath(filePath)

    # Disable pointer-events while resizing
    handles = $("atom-pane-resize-handle")
    handles.on 'mousedown', => @onStartedResize()

  onStartedResize: ->
    @css 'pointer-events': 'none'
    document.addEventListener 'mouseup', @onStoppedResizing.bind this

  onStoppedResizing: ->
    @css 'pointer-events': 'all'
    document.removeEventListener 'mouseup', @onStoppedResizing

  serialize: ->
    deserializer : 'AtomHtmlPreviewView'
    filePath     : @getPath()
    editorId     : @editorId

  destroy: ->
    # @unsubscribe()
    if editorSub?
      @editorSub.dispose()

  subscribeToFilePath: (filePath) ->
    @trigger 'title-changed'
    @handleEvents()
    @renderHTML()

  resolveEditor: (editorId) ->
    resolve = =>
      @editor = @editorForId(editorId)

      if @editor?
        @trigger 'title-changed' if @editor?
        @handleEvents()
      else
        # The editor this preview was created for has been closed so close
        # this preview since a preview cannot be rendered without an editor
        atom.workspace?.paneForItem(this)?.destroyItem(this)

    if atom.workspace?
      resolve()
    else
      # @subscribe atom.packages.once 'activated', =>
      atom.packages.onDidActivatePackage =>
        resolve()
        @renderHTML()

  editorForId: (editorId) ->
    for editor in atom.workspace.getTextEditors()
      return editor if editor.id?.toString() is editorId.toString()
    null

  handleEvents: =>
    contextMenuClientX = 0
    contextMenuClientY = 0

    @on 'contextmenu', (event) ->
      contextMenuClientY = event.clientY
      contextMenuClientX = event.clientX

    atom.commands.add @element,
      'atom-html-preview:open-devtools': =>
        @webview.openDevTools()
      'atom-html-preview:inspect': =>
        @webview.inspectElement(contextMenuClientX, contextMenuClientY)
      'atom-html-preview:print': =>
        @webview.print()


    changeHandler = =>
      @renderHTML()
      pane = atom.workspace.paneForURI(@getURI())
      if pane? and pane isnt atom.workspace.getActivePane()
        pane.activateItem(this)

    @editorSub = new CompositeDisposable

    if @editor?
      if atom.config.get("atom-html-preview.triggerOnSave")
        @editorSub.add @editor.onDidSave changeHandler
      else
        @editorSub.add @editor.onDidStopChanging changeHandler
      @editorSub.add @editor.onDidChangePath => @trigger 'title-changed'

  renderHTML: ->
    @showLoading()
    if @editor?
      if not atom.config.get("atom-html-preview.triggerOnSave") && @editor.getPath()?
        @save(@renderHTMLCode)
      else
        @renderHTMLCode()

  save: (callback) ->
    # Temp file path
    outPath = path.resolve path.join(os.tmpdir(), @editor.getTitle() + ".html")
    out = ""
    fileEnding = @editor.getTitle().split(".").pop()

    if atom.config.get("atom-html-preview.enableMathJax")
      out += """
      <script type="text/x-mathjax-config">
      MathJax.Hub.Config({
      tex2jax: {inlineMath: [['\\\\f$','\\\\f$']]},
      menuSettings: {zoom: 'Click'}
      });
      </script>
      <script type="text/javascript"
      src="http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML">
      </script>
      """

    if atom.config.get("atom-html-preview.preserveWhiteSpaces") and fileEnding in atom.config.get("atom-html-preview.fileEndings")
      # Enclose in <pre> statement to preserve whitespaces
      out += """
      <style type="text/css">
      body { white-space: pre; }
      </style>
      """
    else
      # Add base tag; allow relative links to work despite being loaded
      # as the src of an webview
      out += "<base href=\"" + @getPath() + "\">"

    out += @editor.getText()

    @tmpPath = outPath
    fs.writeFile outPath, out, =>
      try
        @renderHTMLCode()
      catch error
        @showError error

  renderHTMLCode: () ->
    unless @webview?
      webview = document.createElement("webview")
      # Fix from @kwaak (https://github.com/webBoxio/atom-html-preview/issues/1/#issuecomment-49639162)
      # Allows for the use of relative resources (scripts, styles)
      webview.setAttribute("sandbox", "allow-scripts allow-same-origin")
      @webview = webview
      @append $ webview

    @webview.src = @tmpPath
    try
      @find('.show-error').hide()
      @find('.show-loading').hide()
      @webview.reload()

    catch error
      null

    # @trigger('atom-html-preview:html-changed')
    atom.commands.dispatch 'atom-html-preview', 'html-changed'

  getTitle: ->
    if @editor?
      "#{@editor.getTitle()} Preview"
    else
      "HTML Preview"

  getURI: ->
    "html-preview://editor/#{@editorId}"

  getPath: ->
    if @editor?
      @editor.getPath()

  showError: (result) ->
    failureMessage = result?.message

    @find('.show-error')
    .html $$$ ->
      @h2 'Previewing HTML Failed'
      @h3 failureMessage if failureMessage?
    .show()

  showLoading: ->
    @find('.show-loading').show()