_ = require 'underscore-plus'
{$, $$, Range, SelectListView}  = require 'atom'

SuggestionProvider = require './suggestion-provider'

module.exports =
class AutocompleteView extends SelectListView
  suggestionProvider: null
  wordList: null
  wordRegex: /\w+/g
  originalSelectionBufferRanges: null
  aboveCursor: false

  initialize: (@editorView) ->
    super
    @suggestionProvider = new SuggestionProvider(@editorView.editor)
    @addClass('autocomplete popover-list')
    {@editor} = @editorView
    @handleEvents()

  getFilterKey: ->
    'word'

  viewForItem: ({word}) ->
    $$ ->
      @li =>
        @span word

  handleEvents: ->
    @list.on 'mousewheel', (event) -> event.stopPropagation()

    @editorView.on 'editor:path-changed', => @suggestionProvider.setCurrentBuffer(@editor.getBuffer())
    @editorView.command 'autocomplete:toggle', =>
      if @hasParent()
        @cancel()
      else
        @attach()
    @editorView.command 'autocomplete:next', => @selectNextItemView()
    @editorView.command 'autocomplete:previous', => @selectPreviousItemView()

    @filterEditorView.preempt 'textInput', ({originalEvent}) =>
      text = originalEvent.data
      unless text.match(@wordRegex)
        @confirmSelection()
        @editor.insertText(text)
        false

  selectItemView: (item) ->
    super
    if match = @getSelectedItem()
      @suggestionProvider.replaceSelectedTextWithMatch(match)

  selectNextItemView: ->
    super
    false

  selectPreviousItemView: ->
    super
    false

  confirmed: (match) ->
    @suggestionProvider.clearSelection()
    @cancel()
    @suggestionProvider.insertMatch(match)

  cancelled: ->
    super
    @suggestionProvider.stopAutoCompleting() if @suggestionProvider.isCompleting

  attach: ->

    @aboveCursor = false

    return @cancel() unless @suggestionProvider.startAutoCompleting()

    @suggestionProvider.buildWordList()
    matches = @suggestionProvider.findMatchesForCurrentSelection()
    @setItems(matches)

    if matches.length is 1
      @confirmSelection()
    else
      @editorView.appendToLinesView(this)
      @setPosition()
      @focusFilterEditor()

  setPosition: ->
    {left, top} = @editorView.pixelPositionForScreenPosition(@suggestionProvider.originalCursorPosition)
    height = @outerHeight()
    width = @outerWidth()
    potentialTop = top + @editorView.lineHeight
    potentialBottom = potentialTop - @editorView.scrollTop() + height
    parentWidth = @parent().width()

    left = parentWidth - width if left + width > parentWidth

    if @aboveCursor or potentialBottom > @editorView.outerHeight()
      @aboveCursor = true
      @css(left: left, top: top - height, bottom: 'inherit')
    else
      @css(left: left, top: potentialTop, bottom: 'inherit')

  afterAttach: (onDom) ->
    if onDom
      widestCompletion = parseInt(@css('min-width')) or 0
      @list.find('span').each ->
        widestCompletion = Math.max(widestCompletion, $(this).outerWidth())
      @list.width(widestCompletion)
      @width(@list.outerWidth())

  populateList: ->
    super

    @setPosition()
