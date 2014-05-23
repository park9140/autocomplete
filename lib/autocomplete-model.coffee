_ = require 'underscore-plus'
{Range}  = require 'atom'
{Emmitter} = require 'emissary'
async = require 'async'

module.exports =
class AutocompleteModel
  suggestionBuilder: null
  currentBuffer: null
  wordList: []
  wordRegex: /\w+/g
  originalSelectionBufferRanges: null
  originalCursorPosition: null
  aboveCursor: false

  constructor: (@editor, SuggestionProviders) ->
    @setCurrentBuffer(@editor.getBuffer())
    @initialzeSuggestionProviders(suggestionProviders)

  setCurrentBuffer: (@currentBuffer) ->

  initialzeSuggestionProviders: (SuggestionProviders) ->
    @suggestionProviderInstances = suggestionProviders.map SuggestionProvider =>
      new SuggestionProvider(@editor)

  buildWordList: ->
    async.parallel @suggestionProviderInstances.map(
      suggestionProviderInstance ->
        suggestionProviderInstance.buildWordList.bind(
          suggestionProviderInstance
        )
      ),
      wordLists =>
        @wordlist = _.unique(
          _.sort(_.flatten(wordLists), word -> word.word)
          true,
          word -> word.word )

  clearSelection: ->
    @editor.getSelections().forEach (selection) -> selection.clear()

  insertMatch: (match) ->
    return unless match
    @replaceSelectedTextWithMatch match
    @editor.getCursors().forEach (cursor) ->
      position = cursor.getBufferPosition()
      cursor.setBufferPosition([position.row, position.column + match.suffix.length])

  stopAutoCompleting: ->
    @editor.abortTransaction()
    @editor.setSelectedBufferRanges(@originalSelectionBufferRanges)
    @isCompleting = false

  startAutoCompleting: ->
    @isCompleting = true
    @editor.beginTransaction()

    @originalSelectionBufferRanges = @editor.getSelections().map (selection) -> selection.getBufferRange()
    @originalCursorPosition = @editor.getCursorScreenPosition()

    return @allPrefixAndSuffixOfSelectionsMatch()

  findMatchesForCurrentSelection: ->
    selection = @editor.getSelection()
    {prefix, suffix} = @prefixAndSuffixOfSelection(selection)

    if (prefix.length + suffix.length) > 0
      regex = new RegExp("^#{prefix}.+#{suffix}$", "i")
      currentWord = prefix + @editor.getSelectedText() + suffix
      for word in @wordList when regex.test(word) and word != currentWord
        {prefix, suffix, word}
    else
      {word, prefix, suffix} for word in @wordList

  replaceSelectedTextWithMatch: (match) ->
    newSelectedBufferRanges = []
    selections = @editor.getSelections()

    selections.forEach (selection, i) =>
      startPosition = selection.getBufferRange().start
      buffer = @editor.getBuffer()

      selection.deleteSelectedText()
      cursorPosition = @editor.getCursors()[i].getBufferPosition()
      buffer.delete(Range.fromPointWithDelta(cursorPosition, 0, match.suffix.length))
      buffer.delete(Range.fromPointWithDelta(cursorPosition, 0, -match.prefix.length))

      infixLength = match.word.length - match.prefix.length - match.suffix.length

      newSelectedBufferRanges.push([startPosition, [startPosition.row, startPosition.column + infixLength]])

    @editor.insertText(match.word)
    @editor.setSelectedBufferRanges(newSelectedBufferRanges)

  prefixAndSuffixOfSelection: (selection) ->
    selectionRange = selection.getBufferRange()
    lineRange = [[selectionRange.start.row, 0], [selectionRange.end.row, @editor.lineLengthForBufferRow(selectionRange.end.row)]]
    [prefix, suffix] = ["", ""]

    @currentBuffer.scanInRange @wordRegex, lineRange, ({match, range, stop}) ->
      stop() if range.start.isGreaterThan(selectionRange.end)

      if range.intersectsWith(selectionRange)
        prefixOffset = selectionRange.start.column - range.start.column
        suffixOffset = selectionRange.end.column - range.end.column

        prefix = match[0][0...prefixOffset] if range.start.isLessThan(selectionRange.start)
        suffix = match[0][suffixOffset..] if range.end.isGreaterThan(selectionRange.end)

    {prefix, suffix}

  allPrefixAndSuffixOfSelectionsMatch: ->
    {prefix, suffix} = {}

    @editor.getSelections().every (selection) =>
      [previousPrefix, previousSuffix] = [prefix, suffix]

      {prefix, suffix} = @prefixAndSuffixOfSelection(selection)

      return true unless previousPrefix? and previousSuffix?
      prefix is previousPrefix and suffix is previousSuffix

Emitter.includeInto(AutocompleteModel)
