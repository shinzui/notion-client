-- | A request field that can be left out, explicitly cleared with JSON @null@,
-- or set to a value.
--
-- Inside a record encoded with 'genericToJSON' 'aesonOptions', 'Unset' omits
-- the key entirely, 'Clear' writes @null@, and 'Set' writes the value. When
-- decoded with 'genericParseJSON' 'aesonOptions', a missing key becomes 'Unset'
-- and @null@ becomes 'Clear'. (Outside a record, for example as a 'Map' value,
-- 'Unset' also encodes as @null@; use 'Maybe' there instead.)
module Notion.V1.Clearable
  ( Clearable (..),
    clearableToMaybe,
  )
where

import Notion.Prelude

data Clearable a
  = -- | Leave the field unchanged (the key is omitted)
    Unset
  | -- | Clear the field (the key is sent as @null@)
    Clear
  | -- | Set the field to a value
    Set a
  deriving stock (Eq, Show, Generic, Functor, Foldable, Traversable)

instance (ToJSON a) => ToJSON (Clearable a) where
  toJSON = \case
    Unset -> Null
    Clear -> Null
    Set a -> toJSON a
  omitField = \case
    Unset -> True
    _ -> False

instance (FromJSON a) => FromJSON (Clearable a) where
  parseJSON = \case
    Null -> pure Clear
    v -> Set <$> parseJSON v
  omittedField = Just Unset

-- | 'Set' becomes 'Just'; 'Unset' and 'Clear' become 'Nothing'.
clearableToMaybe :: Clearable a -> Maybe a
clearableToMaybe = \case
  Set a -> Just a
  _ -> Nothing
