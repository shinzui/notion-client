let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/026ae74331e5c516542af1dd96f041c658ed4621/package.dhall
        sha256:18258ef583580a897f4af3e7c86db0342afb42fb40efc535b217ba1089230141

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
    , dependencies =
      [ "haskell-servant/servant:servant"
      , "haskell-servant/servant:servant-client"
      , "haskell-servant/servant:servant-client-core"
      , "effectful/effectful:effectful-core"
      ]
    , dependencyRefs =
      [ Schema.MoriRef::{
        , namespace = "haskell-servant"
        , name = "servant"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "servant"
        }
      , Schema.MoriRef::{
        , namespace = "haskell-servant"
        , name = "servant"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "servant-client"
        }
      , Schema.MoriRef::{
        , namespace = "haskell-servant"
        , name = "servant"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "servant-client-core"
        }
      , Schema.MoriRef::{
        , namespace = "effectful"
        , name = "effectful"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "effectful-core"
        }
      ]
    , docs =
      [ Schema.DocRef::{ key = "hackage"
        , kind = Schema.DocKind.Reference
        , audience = Schema.DocAudience.API
        , description = Some "Hackage package page"
        , location =
            Schema.DocLocation.Url
              "https://hackage.haskell.org/package/notion-client"
        }
      ]
    }
