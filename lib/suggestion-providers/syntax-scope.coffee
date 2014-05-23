_ = require 'underscore-plus'
{Range}  = require 'atom'

module.exports =
class SuggestionProvider
  suggestionBuilder: null
  currentBuffer: null
  wordList: []
  wordRegex: /\w+/g
  originalSelectionBufferRanges: null
  originalCursorPosition: null
  aboveCursor: false

  constructor: (@editor) ->
    @setCurrentBuffer(@editor.getBuffer())

  setCurrentBuffer: (@currentBuffer) ->

  getCompletionsForCursorScope: ->
    cursorScope = @editor.scopesForBufferPosition(@editor.getCursorBufferPosition())
    completions = atom.syntax.propertiesForScope(cursorScope, 'editor.completions')
    completions = completions.map (properties) -> _.valueForKeyPath(properties, 'editor.completions')
    _.uniq(_.flatten(completions))

  buildWordList: ->
    wordHash = {}
    if atom.config.get('autocomplete.includeCompletionsFromAllBuffers')
      buffers = atom.project.getBuffers()
    else
      buffers = [@currentBuffer]
    matches = []
    matches.push(buffer.getText().match(@wordRegex)) for buffer in buffers
    wordHash[word] ?= true for word in _.flatten(matches) when word
    wordHash[word] ?= true for word in @getCompletionsForCursorScope() when word

    return @wordList = Object.keys(wordHash).sort (word1, word2) ->
      word1.toLowerCase().localeCompare(word2.toLowerCase())

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

    @originalSelectionBucfferRanges = @editor.getSelections().map (selection) -> selection.getBufferRange()
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
