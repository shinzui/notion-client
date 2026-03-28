let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/8415b4b8a746a84eecf982f0f1d7194368bf7b54/package.dhall
        sha256:d19ae156d6c357d982a1aea0f1b6ba1f01d76d2d848545b150db75ed4c39a8a9

let Dependency = Schema.Dependency

let DocRef = Schema.DocRef

let ApiSource = Schema.ApiSource

let ConfigItem = Schema.ConfigItem

in  { project =
      { name = "notion-client"
      , namespace = "shinzui"
      , type = Schema.PackageType.Library
      , description = Some
          "Type-safe Haskell client for the Notion API using Servant"
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , domains = [ "notion", "api-client" ]
      , owners = [ "shinzui" ]
      , origin = Schema.Origin.Own
      }
    , repos =
      [ { name = "notion-client"
        , github = Some "shinzui/notion-client"
        , gitlab = None Text
        , git = None Text
        , localPath = None Text
        }
      ]
    , packages =
      [ { name = "notion-client"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./"
        , description = Some
            "Type-safe Notion API bindings with Servant interface"
        , lifecycle = None Schema.Lifecycle
        , visibility = Schema.Visibility.Public
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies = [] : List Dependency
        , docs = [] : List DocRef
        , config = [] : List ConfigItem
        , apiSource = None ApiSource
        }
      , { name = "notion-client-example"
        , type = Schema.PackageType.Tool
        , language = Schema.Language.Haskell
        , path = Some "notion-client-example/"
        , description = Some "Example usage of the notion-client library"
        , lifecycle = None Schema.Lifecycle
        , visibility = Schema.Visibility.Internal
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies = [] : List Dependency
        , docs = [] : List DocRef
        , config = [] : List ConfigItem
        , apiSource = None ApiSource
        }
      , { name = "notion-client-test"
        , type = Schema.PackageType.Other "test-suite"
        , language = Schema.Language.Haskell
        , path = Some "tasty/"
        , description = Some "Test suite for notion-client"
        , lifecycle = None Schema.Lifecycle
        , visibility = Schema.Visibility.Internal
        , runtime = { deployable = False, exposesApi = False }
        , runtimeEnvironment = None Schema.RuntimeEnvironment
        , dependencies = [] : List Dependency
        , docs = [] : List DocRef
        , config = [] : List ConfigItem
        , apiSource = None ApiSource
        }
      ]
    , bundles = [] : List Schema.PackageBundle
    , dependencies = [ "haskell-servant/servant" ]
    , apis = [] : List Schema.Api
    , agents = [] : List Schema.AgentHint
    , skills = [] : List Schema.Skill
    , subagents = [] : List Schema.Subagent
    , standards = [] : List Text
    , docs =
      [ { key = "readme"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Getting started and usage examples"
        , location = Schema.DocLocation.LocalFile "README.md"
        }
      , { key = "changelog"
        , kind = Schema.DocKind.Notes
        , audience = Schema.DocAudience.User
        , description = Some "Release history"
        , location = Schema.DocLocation.LocalFile "CHANGELOG.md"
        }
      , { key = "architecture"
        , kind = Schema.DocKind.Reference
        , audience = Schema.DocAudience.Module
        , description = Some
            "Architecture notes for API 2025-09-03 migration"
        , location = Schema.DocLocation.LocalFile "architecture.md"
        }
      , { key = "hackage"
        , kind = Schema.DocKind.Reference
        , audience = Schema.DocAudience.API
        , description = Some "Hackage package page"
        , location =
            Schema.DocLocation.Url
              "https://hackage.haskell.org/package/notion-client"
        }
      ]
    }
