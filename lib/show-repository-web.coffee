{CompositeDisposable} = require 'atom'
Shell = require 'shell'
GitUrlParse = require 'git-url-parse'

module.exports = ShowRepositoryWeb =
  subscriptions: null

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-workspace', 'show-repository-web:open-in-browser': => @openInBrowser()
    @subscriptions.add atom.commands.add 'atom-workspace', 'show-repository-web:copy-url': => @copyUrl()

  deactivate: ->
    @subscriptions.dispose()

  serialize: ->
    showRepositoryWebViewState: @showRepositoryWebView.serialize()

  openInBrowser: ->
    @getUrl().then(
      (url) ->
        Shell.openExternal url
        atom.notifications.addInfo(
          'Opening repository URL in browser.'
          { detail: url }
        )
      @notifyGetUrlError
    )

  copyUrl: ->
    @getUrl().then(
      (url) ->
        atom.clipboard.write url
        atom.notifications.addInfo(
          'Repository URL was copied to clipboard.'
          { detail: url }
        )
      @notifyGetUrlError
    )

  notifyGetUrlError: (code) ->
    message = switch code
      when 'no-git' then 'Init repository first.'
      when 'modified' then 'Commit file first.'
      when 'new' then 'Commit file first.'
      else 'Unknown error.'
    atom.notifications.addError code, { detail: message }

  getGitInfo: (path) ->
    new Promise (resolve, reject) ->
      repoDirectory = null
      for directory in atom.project.getDirectories()
        if directory.contains path
          repoDirectory = directory
          break
      if ! repoDirectory # unreachable condition?
        reject 'no-directory'
        return

      atom.project.repositoryForDirectory(repoDirectory)
      .then(
        (repository) ->
          if repository.isPathIgnored path
            reject 'ignored'
            return
          if repository.isPathNew path
            reject 'new'
            return
          if repository.isPathModified path
            reject 'modified'
            return
          branch = repository.getUpstreamBranch path
          if ! branch
            reject 'no-upstream-branch'
            return
          s = branch.split('/', 4)
          if s[0] != 'refs' or s[1] != 'remotes'
            reject 'unsupported-ref'
            return
          resolve [
            GitUrlParse(
              repository.getConfigValue(
                'remote.' + s[2] + '.url'
                path
              )
            )
            s[3]
            repository.relativize path
          ]
        -> reject 'no-repository'
      )

  getUrl: ->
    editor = atom.workspace.getActiveTextEditor()
    path = editor.getPath()
    range = editor.getSelectedBufferRange()
    new Promise (resolve, reject) ->
      ShowRepositoryWeb.getGitInfo(
        path
      ).then(
        ([parsed, branch, filename]) ->
          resolve ShowRepositoryWeb.getRepositoryWebUrl(
            parsed
            branch
            filename
            range
          )
        reject
      )

  getRepositoryWebUrl: (info, branch, path, range) ->
    switch
      when info.resource is 'github.com', info.resource.indexOf('github.') is 0
        format = 'github'
      when info.resource is 'gitlab.com', info.resource.indexOf('gitlab.') is 0
        format = 'gitlab'

    switch format
      when 'github'
        @formatGithubUrl(
          info
          branch
          path
          range
        )
      when 'gitlab'
        @formatGitlabUrl(
          info
          branch
          path
          range
        )

  formatGitlabUrl: (info, branch, path, range) ->
    "https://#{ info.resource }" +
    "/#{ encodeURIComponent(info.owner) }/#{ encodeURIComponent(info.name) }" +
    "/blob" +
    "/#{ encodeURIComponent(branch) }/#{ @encodeSegments(path) }" +
    switch
      when range.start.row is range.end.row
        "#L#{ range.start.row+1}"
      else
        "#L#{ range.start.row+1 }:#{ range.end.row+1 }"

  formatGithubUrl: (info, branch, path, range) ->
    "https://#{ info.resource }" +
    "/#{ encodeURIComponent(info.owner) }/#{ encodeURIComponent(info.name) }" +
    "/blob" +
    "/#{ encodeURIComponent(branch) }/#{ @encodeSegments(path) }" +
    switch
      when range.start.row is range.end.row
        "#L#{ range.start.row+1}"
      else
        "#L#{ range.start.row+1 }:L#{ range.end.row+1 }"

  encodeSegments: (segments='') ->
    segments = segments.split('/')
    segments = segments.map (segment) -> encodeURIComponent(segment)
    segments.join('/')
