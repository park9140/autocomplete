_ = require 'underscore-plus'
AutocompleteView = require './autocomplete-view'
SuggestionProvider = require './suggestion-provider'

module.exports =
  configDefaults:
    includeCompletionsFromAllBuffers: false

  autocompleteViews: []
  editorSubscription: null

  activate: ->
    SuggestionProviders @getSuggestionProviders()
    @editorSubscription = atom.workspaceView.eachEditorView (editor) =>
      if editor.attached and not editor.mini
        autocompleteView = new AutocompleteView(editor)
        editor.on 'editor:will-be-removed', =>
          autocompleteView.remove() unless autocompleteView.hasParent()
          _.remove(@autocompleteViews, autocompleteView)
        @autocompleteViews.push(autocompleteView)

  getSuggestionProviders: ->
    SuggestionProviders = []

    for atomPackage in atom.packages.getLoadedPackages()
      if atomPackage.metadata['suggestion-providers']?
        SuggestionProviderLocations =
          atomPackage.metadata['suggestion-providers']
        for SuggestionProviderLocation in SuggestionProviderLocations
          SuggestionProviders.push(
            require "#{atomPackage.path}#{SuggestionProviderLocation}"
          )

    return SuggestionProviders

  deactivate: ->
    @editorSubscription?.off()
    @editorSubscription = null
    @autocompleteViews.forEach (autocompleteView) -> autocompleteView.remove()
    @autocompleteViews = []

  SuggestionProvider: SuggestionProvider
