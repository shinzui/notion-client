-- | Response serialization and request isolation, using only scripted HTTP.
module ResponseJSONTests (tests) where

import Control.Monad (forM_)
import Data.Aeson ((.=))
import Data.Aeson qualified as A
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Map qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as V
import FakeNotion (fakeClientEnv, jsonReply)
import Notion.V1 (Methods (..), defaultClientConfig, makeMethodsWithEnv)
import Notion.V1.Common (Parent (..))
import Notion.V1.DataSources (PageOrDataSource (..), _QueryDataSource)
import Notion.V1.ListOf qualified as List
import Notion.V1.Pages qualified as Pages
import Notion.V1.PropertyValue hiding (date, id)
import Notion.V1.RichText qualified as RT
import Notion.V1.Search (_SearchRequest)
import Notion.V1.Users qualified as U
import Test.Tasty
import Test.Tasty.HUnit

fromValue :: (A.FromJSON a) => A.Value -> IO a
fromValue v = case A.fromJSON v of
  A.Success a -> pure a
  A.Error e -> assertFailure e

field :: K.Key -> A.Value -> A.Value
field key (A.Object o) = maybe A.Null id (KM.lookup key o)
field _ _ = A.Null

hasField :: K.Key -> A.Value -> Bool
hasField key (A.Object o) = KM.member key o
hasField _ _ = False

prop :: Text -> A.Value -> A.Value
prop t v = A.object ["id" .= ("x%3Ay" :: Text), "type" .= t, K.fromText t .= v]

relation :: Maybe Bool -> [A.Value] -> A.Value
relation flag refs =
  A.object $
    ["id" .= ("rel" :: Text), "type" .= ("relation" :: Text), "relation" .= refs]
      <> maybe [] (\b -> ["has_more" .= b]) flag

userRef :: A.Value
userRef = A.object ["object" .= ("user" :: Text), "id" .= ("u1" :: Text)]

person :: A.Value
person =
  A.object
    [ "object" .= ("user" :: Text),
      "id" .= ("u1" :: Text),
      "type" .= ("person" :: Text),
      "name" .= ("Ada" :: Text),
      "avatar_url" .= ("https://example.com/avatar" :: Text),
      "person" .= A.object ["email" .= ("ada@example.com" :: Text)]
    ]

date :: A.Value
date = A.object ["start" .= ("2026-10-12" :: Text), "end" .= ("2026-10-13" :: Text), "time_zone" .= ("UTC" :: Text)]

mention :: A.Value -> A.Value
mention m =
  A.object
    [ "type" .= ("mention" :: Text),
      "plain_text" .= ("Ada" :: Text),
      "href" .= ("https://example.com/user" :: Text),
      "annotations" .= RT.defaultAnnotations,
      "mention" .= m
    ]

userMention :: A.Value
userMention = mention (A.object ["type" .= ("user" :: Text), "user" .= person])

-- Check the typed constructor independently so an unknown fallback cannot hide
-- a failed known decoder while still passing the structural equality assertion.
constructorKind :: PropertyValue -> Text
constructorKind = \case
  TitleValue {} -> "title"
  RichTextValue {} -> "rich_text"
  NumberValue {} -> "number"
  SelectValue {} -> "select"
  MultiSelectValue {} -> "multi_select"
  DateValue {} -> "date"
  PeopleValue {} -> "people"
  FilesValue {} -> "files"
  CheckboxValue {} -> "checkbox"
  UrlValue {} -> "url"
  EmailValue {} -> "email"
  PhoneNumberValue {} -> "phone_number"
  FormulaValue {} -> "formula"
  RelationValue {} -> "relation"
  RollupValue {} -> "rollup"
  CreatedTimeValue {} -> "created_time"
  CreatedByValue {} -> "created_by"
  LastEditedTimeValue {} -> "last_edited_time"
  LastEditedByValue {} -> "last_edited_by"
  StatusValue {} -> "status"
  UniqueIdValue {} -> "unique_id"
  PlaceValue {} -> "place"
  ButtonValue {} -> "button"
  VerificationValue {} -> "verification"
  UnknownPropertyValue {} -> "unknown"

fixtures :: [(Text, A.Value)]
fixtures =
  [ ("title", A.toJSON [userMention]),
    ("rich_text", A.toJSON [userMention]),
    ("number", A.Number 42),
    ("select", option),
    ("multi_select", A.toJSON [option]),
    ("date", date),
    ("people", A.toJSON [person, userRef, A.object ["object" .= ("group" :: Text), "id" .= ("g1" :: Text), "name" .= ("Team" :: Text)]]),
    ( "files",
      A.toJSON
        [ A.object ["type" .= ("external" :: Text), "name" .= ("Link" :: Text), "external" .= A.object ["url" .= ("https://example.com/file" :: Text)]],
          A.object ["type" .= ("file" :: Text), "name" .= ("File" :: Text), "file" .= A.object ["url" .= ("https://example.com/file" :: Text), "expiry_time" .= ("2026-10-13T00:00:00Z" :: Text)]],
          A.object ["type" .= ("file_upload" :: Text), "name" .= ("Upload" :: Text), "file_upload" .= A.object ["id" .= ("f1" :: Text)]]
        ]
    ),
    ("checkbox", A.Bool False),
    ("url", A.String "https://example.com"),
    ("email", A.String "ada@example.com"),
    ("phone_number", A.String "555-0123"),
    ("formula", A.object ["type" .= ("number" :: Text), "number" .= (4 :: Int)]),
    ("relation", A.toJSON [A.object ["id" .= ("p2" :: Text)]]),
    ("rollup", A.object ["type" .= ("number" :: Text), "number" .= (4 :: Int), "function" .= ("sum" :: Text)]),
    ("created_time", A.String "2026-10-12T00:00:00Z"),
    ("created_by", userRef),
    ("last_edited_time", A.String "2026-10-13T00:00:00Z"),
    ("last_edited_by", userRef),
    ("status", option),
    ("unique_id", A.object ["number" .= (7 :: Int), "prefix" .= ("TASK" :: Text)]),
    ("place", A.object ["lat" .= (1 :: Int), "lon" .= (2 :: Int), "name" .= ("Home" :: Text), "address" .= ("Main St" :: Text), "aws_place_id" .= ("aws1" :: Text), "google_place_id" .= ("google1" :: Text)]),
    ("button", A.object ["arbitrary" .= True]),
    ("verification", A.object ["state" .= ("verified" :: Text), "verified_by" .= person, "date" .= date]),
    ("future_property", A.object ["raw" .= [True, False]])
  ]
  where
    option = A.object ["id" .= ("o1" :: Text), "name" .= ("Ready" :: Text), "color" .= ("green" :: Text), "description" .= ("Next" :: Text)]

checkProperty :: Text -> A.Value -> Assertion
checkProperty kind raw = do
  p <- fromValue raw
  constructorKind p @?= kind
  propertyValueResponseJSON p @?= raw

relationTests :: TestTree
relationTests =
  testGroup
    "Relations"
    [ testGroup
        "Relation metadata"
        [ testCase (show flag <> "/" <> show count) $ do
            let raw = relation flag (replicate count (A.object ["id" .= ("p2" :: Text)]))
            p <- fromValue raw
            case p of
              RelationValue pid refs retained -> do
                pid @?= "rel"
                V.length refs @?= count
                retained @?= flag
              other -> assertFailure (show other)
            propertyValueResponseJSON p @?= raw
            hasField "has_more" (propertyValueResponseJSON p) @?= maybe False (const True) flag
        | flag <- [Just True, Just False, Nothing],
          count <- [0, 1, 25]
        ],
      testGroup
        "Flag decoding"
        [ testCase "null is absent" $ do
            p <- fromValue (setField "has_more" A.Null (relation Nothing []))
            case p of
              RelationValue _ _ flag -> flag @?= Nothing
              other -> assertFailure (show other),
          testCase "malformed flag is an error" $
            case A.fromJSON @PropertyValue (setField "has_more" (A.String "true") (relation Nothing [])) of
              A.Error _ -> pure ()
              A.Success p -> assertFailure (show p)
        ]
    ]

setField :: K.Key -> A.Value -> A.Value -> A.Value
setField key v (A.Object o) = A.Object (KM.insert key v o)
setField _ _ v = v

tests :: TestTree
tests =
  testGroup
    "Response JSON"
    [ relationTests,
      testGroup "Every constructor" [testCase (Text.unpack t) (checkProperty (if t == "future_property" then "unknown" else t) (prop t v)) | (t, v) <- fixtures],
      testGroup "Nullable values" [testCase (Text.unpack t) (checkProperty t (prop t A.Null)) | t <- ["number", "select", "date", "url", "email", "phone_number", "status", "place", "button", "verification"]],
      formulaTests,
      rollupTests,
      userTests,
      mutationTests,
      pageTests
    ]

formulaTests :: TestTree
formulaTests =
  testGroup
    "Formulas"
    [ testCase (Text.unpack t <> if v == A.Null then " null" else " populated") $ do
        let raw = A.object ["type" .= t, K.fromText t .= v]
        p <- fromValue (prop "formula" raw)
        case p of
          FormulaValue _ r -> assertBool "typed formula constructor" (typedFormula t r)
          other -> assertFailure (show other)
        propertyValueResponseJSON p @?= prop "formula" raw
    | (t, v) <- [("string", A.String "text"), ("string", A.Null), ("number", A.Number 4), ("number", A.Null), ("boolean", A.Bool False), ("boolean", A.Null), ("date", date), ("date", A.Null), ("unsupported", A.object []), ("future_formula", A.object ["raw" .= True])]
    ]
  where
    typedFormula "string" FormulaStringResult {} = True
    typedFormula "number" FormulaNumberResult {} = True
    typedFormula "boolean" FormulaBooleanResult {} = True
    typedFormula "date" FormulaDateResult {} = True
    typedFormula "unsupported" FormulaUnsupportedResult = True
    typedFormula "future_formula" UnknownFormulaResult {} = True
    typedFormula _ _ = False

rollupTests :: TestTree
rollupTests =
  testGroup
    "Rollup responses"
    [ testGroup
        "Rollups"
        [ testCase (Text.unpack t <> if v == A.Null then " null" else " populated") $ do
            let raw = A.object (["type" .= t, "function" .= ("show_original" :: Text)] <> [K.fromText t .= v | t `notElem` ["incomplete", "unsupported"]])
            p <- fromValue (prop "rollup" raw)
            case p of
              RollupValue _ r -> assertBool "typed rollup constructor" (typedRollup t r)
              other -> assertFailure (show other)
            propertyValueResponseJSON p @?= prop "rollup" raw
        | (t, v) <- [("number", A.Number 4), ("number", A.Null), ("date", date), ("date", A.Null), ("incomplete", A.Null), ("unsupported", A.Null), ("future_rollup", A.object ["raw" .= True]), ("array", A.toJSON [A.object ["type" .= ("rollup" :: Text), "rollup" .= nested]])]
        ],
      testGroup
        "Nested arrays"
        [ testCase "ID-less relations and unknown entries recur; mutation remains request-shaped" $ do
            p <- fromValue (prop "rollup" nested)
            case p of
              RollupValue _ (RollupArrayResult entries _) -> case V.toList entries of
                [RelationValue pid _ flag, UnknownPropertyValue unknownId t _] -> do
                  pid @?= ""
                  flag @?= Just True
                  unknownId @?= ""
                  t @?= "future_nested"
                other -> assertFailure (show other)
              other -> assertFailure (show other)
            propertyValueResponseJSON p @?= prop "rollup" nested
            let entries = field "array" (field "rollup" (A.toJSON p))
            case entries of
              A.Array vs -> forM_ vs $ \v -> forM_ ["id", "type", "has_more"] $ \key -> assertBool "mutation envelope" (not (hasField key v))
              other -> assertFailure (show other)
        ]
    ]
  where
    nested =
      A.object
        [ "type" .= ("array" :: Text),
          "function" .= ("show_original" :: Text),
          "array"
            .= [ A.object ["type" .= ("relation" :: Text), "relation" .= ([] :: [A.Value]), "has_more" .= True],
                 A.object ["type" .= ("future_nested" :: Text), "future_nested" .= A.object ["raw" .= True]]
               ]
        ]
    typedRollup "number" RollupNumberResult {} = True
    typedRollup "date" RollupDateResult {} = True
    typedRollup "array" RollupArrayResult {} = True
    typedRollup "incomplete" RollupIncompleteResult {} = True
    typedRollup "unsupported" RollupUnsupportedResult {} = True
    typedRollup "future_rollup" RollupUnknownResult {} = True
    typedRollup _ _ = False

userTests :: TestTree
userTests =
  testGroup
    "Users"
    [ testGroup
        "Response users"
        [ testCase "full people, partial people and groups remain typed" $ do
            p <- fromValue (prop "people" (A.toJSON [person, userRef, A.object ["object" .= ("group" :: Text), "id" .= ("g1" :: Text)]]))
            case p of
              PeopleValue _ entries -> case V.toList entries of
                [U.PersonEntry (U.FullUser _), U.PersonEntry (U.PartialUser _), U.GroupEntry _] -> pure ()
                other -> assertFailure (show other)
              other -> assertFailure (show other)
            field "people" (A.toJSON p) @?= A.toJSON [userRef, userRef, A.object ["object" .= ("group" :: Text), "id" .= ("g1" :: Text)]],
          testCase "title, rich text and verification keep typed full users" $ do
            forM_ ["title", "rich_text"] $ \t -> do
              p <- fromValue (prop t (A.toJSON [userMention]))
              let entries = case p of TitleValue _ es -> es; RichTextValue _ es -> es; _ -> V.empty
              case V.toList entries of
                [RT.RichText {RT.content = RT.MentionContentWrapper (RT.UserMention (U.FullUser _))}] -> pure ()
                other -> assertFailure (show other)
              propertyValueResponseJSON p @?= prop t (A.toJSON [userMention])
              field "user" (field "mention" (case field (K.fromText t) (A.toJSON p) of A.Array vs -> V.head vs; _ -> A.Null)) @?= userRef
            p <- fromValue (prop "verification" (A.object ["state" .= ("verified" :: Text), "verified_by" .= person, "date" .= date]))
            case p of
              VerificationValue _ (Just VerificationResult {verifiedBy = Just (U.FullUser _)}) -> pure ()
              other -> assertFailure (show other)
            field "verified_by" (field "verification" (A.toJSON p)) @?= userRef,
          testCase "other and unknown mentions preserve their existing envelopes"
            $ forM_
              [ A.object ["type" .= ("page" :: Text), "page" .= A.object ["id" .= ("p2" :: Text)]],
                A.object ["type" .= ("future_mention" :: Text), "future_mention" .= A.object ["raw" .= True]]
              ]
            $ \m -> checkProperty "rich_text" (prop "rich_text" (A.toJSON [mention m])),
          testCase "absent person details are omitted" $
            checkProperty "people" (prop "people" (A.toJSON [A.object ["object" .= ("user" :: Text), "id" .= ("u1" :: Text), "type" .= ("person" :: Text), "person" .= A.object []]]))
        ],
      testGroup
        "Bot owners"
        [ testCase (show (field "type" owner)) $ do
            let bot =
                  A.object
                    [ "object" .= ("user" :: Text),
                      "id" .= ("b1" :: Text),
                      "type" .= ("bot" :: Text),
                      "bot"
                        .= A.object
                          [ "owner" .= owner,
                            "workspace_name" .= ("Team" :: Text),
                            "workspace_id" .= ("w1" :: Text),
                            "workspace_limits" .= A.object ["max_file_upload_size_in_bytes" .= (100000 :: Int)]
                          ]
                    ]
            p <- fromValue (prop "people" (A.toJSON [bot]))
            case p of
              PeopleValue _ es -> case V.toList es of
                [U.PersonEntry (U.FullUser U.UserObject {U.bot = Just U.BotUser {U.owner = Just o}})] -> assertBool "typed owner" (ownerKind owner o)
                other -> assertFailure (show other)
              other -> assertFailure (show other)
            propertyValueResponseJSON p @?= prop "people" (A.toJSON [bot])
        | owner <-
            [ A.object ["type" .= ("user" :: Text), "user" .= A.object ["id" .= ("u1" :: Text)]],
              A.object ["type" .= ("workspace" :: Text), "workspace" .= False],
              A.object ["type" .= ("future_owner" :: Text), "future_owner" .= [True, False]]
            ]
        ]
    ]
  where
    ownerKind raw o = case (field "type" raw, o) of
      (A.String "user", U.UserOwner {}) -> True
      (A.String "workspace", U.WorkspaceOwner {}) -> True
      (A.String "future_owner", U.UnknownOwner {}) -> True
      _ -> False

mutationTests :: TestTree
mutationTests =
  testGroup
    "Mutation isolation"
    [ testCase "decoded true and false relations retain only their request payload" $ forM_ [True, False] $ \b -> do
        p <- fromValue @PropertyValue (relation (Just b) [A.object ["id" .= ("p2" :: Text)]])
        A.toJSON p @?= A.object ["relation" .= [A.object ["id" .= ("p2" :: Text)]]],
      testCase "smart constructors retain their signatures and request JSON" $ do
        let p = relationValue ["p2"]
        case p of
          RelationValue pid refs flag -> do pid @?= ""; V.length refs @?= 1; flag @?= Nothing
          other -> assertFailure (show other)
        A.toJSON p @?= A.object ["relation" .= [A.object ["id" .= ("p2" :: Text)]]]
        A.toJSON (peopleValue ["u1"]) @?= A.object ["people" .= [userRef]],
      testCase "create and update property envelopes keep legitimate nested IDs" $ do
        rel <- fromValue (relation (Just True) [A.object ["id" .= ("p2" :: Text)]])
        people <- fromValue (prop "people" (A.toJSON [person]))
        let ps = Map.fromList [("Related", rel), ("People", people)]
            expected = A.object ["Related" .= A.object ["relation" .= [A.object ["id" .= ("p2" :: Text)]]], "People" .= A.object ["people" .= [userRef]]]
        forM_ [A.toJSON (Pages.mkCreatePage (WorkspaceParent True) ps), A.toJSON (Pages.mkUpdatePage ps)] $ \request -> do
          field "properties" request @?= expected
          forM_ ["Related", "People"] $ \name -> forM_ ["id", "type", "has_more"] $ \key ->
            assertBool "no response metadata at property envelope" (not (hasField key (field name (field "properties" request))))
    ]

pageFixture :: Bool -> A.Value
pageFixture populated =
  A.object $
    [ "object" .= ("page" :: Text),
      "id" .= ("p1" :: Text),
      "created_time" .= ("2026-10-12T00:00:00Z" :: Text),
      "last_edited_time" .= ("2026-10-13T00:00:00Z" :: Text),
      "created_by" .= userRef,
      "last_edited_by" .= userRef,
      "parent" .= A.object ["type" .= ("workspace" :: Text), "workspace" .= True],
      "in_trash" .= False,
      "url" .= ("https://www.notion.so/p1" :: Text),
      "cover" .= if populated then A.object ["type" .= ("external" :: Text), "external" .= A.object ["url" .= ("https://example.com/cover" :: Text)]] else A.Null,
      "icon" .= if populated then A.object ["type" .= ("emoji" :: Text), "emoji" .= ("📚" :: Text)] else A.Null,
      "properties" .= A.object ["Related" .= relation (Just True) [], "People" .= prop "people" (A.toJSON [person])]
    ]
      <> if populated then ["is_locked" .= False, "is_archived" .= False, "public_url" .= ("https://example.com/public" :: Text)] else []

checkPage :: Bool -> Pages.PageObject -> Assertion
checkPage populated page@Pages.PageObject {Pages.properties = ps} = do
  let raw = pageFixture populated
      encoded = Pages.pageResponseJSON page
  forM_ ["id", "object", "created_time", "last_edited_time", "created_by", "last_edited_by", "parent", "in_trash", "url", "cover", "icon"] $ \key -> do
    assertBool ("page field present: " <> show key) (hasField key encoded)
    assertEqual (show key) (field key raw) (field key encoded)
  forM_ ["is_locked", "is_archived", "public_url"] $ \key -> do
    hasField key encoded @?= populated
    field key encoded @?= field key raw
  field "properties" encoded @?= field "properties" raw
  let old = A.toJSON page
  field "Related" (field "properties" old) @?= A.object ["relation" .= ([] :: [A.Value])]
  field "People" (field "properties" old) @?= A.object ["people" .= [userRef]]
  case Map.lookup "Related" ps of
    Just (RelationValue pid refs flag) -> do pid @?= "rel"; V.null refs @?= True; flag @?= Just True
    other -> assertFailure (show other)

withReply :: A.Value -> (Methods -> IO a) -> IO a
withReply raw call = do
  (env, _) <- fakeClientEnv [jsonReply 200 (A.encode raw)]
  call (makeMethodsWithEnv defaultClientConfig env "test-token")

pageTests :: TestTree
pageTests =
  testGroup
    "Pages"
    [ testGroup
        "Page integration"
        [ testCase "retrievePage retains relation metadata through the public encoder" $
            withReply (pageFixture False) (\m -> retrievePage m "p1") >>= checkPage False,
          testCase "createPage retains relation metadata through the public encoder" $
            withReply (pageFixture True) (\m -> createPage m (Pages.mkCreatePage (WorkspaceParent True) Map.empty)) >>= checkPage True,
          testCase "missing optional page fields follow existing null and omission rules" $ do
            let A.Object raw = pageFixture False
            page <- fromValue @Pages.PageObject (A.Object (KM.delete "icon" (KM.delete "cover" raw)))
            checkPage False page
        ],
      testGroup
        "Full and partial lists"
        [ testCase name $ do
            list <- withReply rows call
            case V.toList (List.results list) of
              [PageResult p, PartialPageResult _, PartialDataSourceResult _, UnknownResult unknown] -> do
                checkPage True p
                unknown @?= future
              other -> assertFailure (show other)
            List.hasMore list @?= False
        | (name, call) <- [("queryDataSource", \m -> queryDataSource m "ds1" _QueryDataSource), ("search", \m -> search m _SearchRequest)]
        ]
    ]
  where
    future = A.object ["object" .= ("future_object" :: Text), "raw" .= True]
    rows =
      A.object
        [ "object" .= ("list" :: Text),
          "results"
            .= [ pageFixture True,
                 A.object ["object" .= ("page" :: Text), "id" .= ("p2" :: Text)],
                 A.object ["object" .= ("data_source" :: Text), "id" .= ("ds2" :: Text)],
                 future
               ],
          "next_cursor" .= A.Null,
          "has_more" .= False
        ]
