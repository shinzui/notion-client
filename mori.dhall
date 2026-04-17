let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/ad9960dd3dd3b33eadd45f17bcf430b0e1ec13bc/package.dhall
        sha256:83aa1432e98db5da81afde4ab2057dcab7ce4b2e883d0bc7f16c7d25b917dd0c

in  Schema.Project::{ project =
      Schema.ProjectIdentity::{ name = "notion-client"
      , namespace = "shinzui"
      , type = Schema.PackageType.Library
      , description = Some
          "Type-safe Haskell client for the Notion API using Servant"
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , domains = [ "notion", "api-client" ]
      , owners = [ "shinzui" ]
      }
    , repos =
      [ Schema.Repo::{ name = "notion-client"
        , github = Some "shinzui/notion-client"
        }
      ]
    , packages =
      [ Schema.Package::{ name = "notion-client"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./"
        , description = Some
            "Type-safe Notion API bindings with Servant interface"
        }
      , Schema.Package::{ name = "notion-client-example"
        , type = Schema.PackageType.Tool
        , language = Schema.Language.Haskell
        , path = Some "notion-client-example/"
        , description = Some "Example usage of the notion-client library"
        , visibility = Schema.Visibility.Internal
        }
      , Schema.Package::{ name = "notion-client-test"
        , type = Schema.PackageType.Other "test-suite"
        , language = Schema.Language.Haskell
        , path = Some "tasty/"
        , description = Some "Test suite for notion-client"
        , visibility = Schema.Visibility.Internal
        }
      , Schema.Package::{ name = "notion-client-effectful"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "notion-client-effectful/"
        , description = Some
            "Effectful effect + interpreter for notion-client"
        }
      ]
    , dependencies = [ "haskell-servant/servant" ]
    , docs =
      [ Schema.DocRef::{ key = "readme"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Getting started and usage examples"
        , location = Schema.DocLocation.LocalFile "README.md"
        }
      , Schema.DocRef::{ key = "changelog"
        , kind = Schema.DocKind.Notes
        , audience = Schema.DocAudience.User
        , description = Some "Release history"
        , location = Schema.DocLocation.LocalFile "CHANGELOG.md"
        }
      , Schema.DocRef::{ key = "architecture"
        , kind = Schema.DocKind.Reference
        , audience = Schema.DocAudience.Module
        , description = Some
            "Architecture notes for API 2025-09-03 migration"
        , location = Schema.DocLocation.LocalFile "architecture.md"
        }
      , Schema.DocRef::{ key = "hackage"
        , kind = Schema.DocKind.Reference
        , audience = Schema.DocAudience.API
        , description = Some "Hackage package page"
        , location =
            Schema.DocLocation.Url
              "https://hackage.haskell.org/package/notion-client"
        }
      ]
    }
