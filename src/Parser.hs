module Parser where

import           Prelude                        ( )
import           Relude                  hiding ( take
                                                , takeWhile
                                                )

import           Data.Text               hiding ( take
                                                , takeWhile
                                                )
import           Data.Attoparsec.Text.Lazy


data ParseResult =
   Uploading StorePath Host
 | Downloading StorePath Host
 | PlanCopies Int
 | RemoteBuild Derivation Host
 | LocalBuild Derivation
 | NotRecognized
 | PlanBuilds (Set Derivation)
 | PlanDownloads Double Double (Set StorePath)
 deriving (Show, Eq, Read)

parser :: Parser ParseResult
parser = planBuilds <|> planDownloads <|> copying <|> building <|> noMatch

data StorePath = StorePath
  { hash :: Text
  , name :: Text
  }
  deriving stock (Show, Ord, Eq, Read)

newtype Derivation = Derivation { toStorePath :: StorePath } deriving stock (Show, Ord, Eq, Read)

instance ToText Derivation where
  toText = (<> ".drv") . toText . toStorePath
instance ToString Derivation where
  toString = toString . toText

storePrefix :: Text
storePrefix = "/nix/store/"

instance ToText StorePath where
  toText (StorePath hash name) = storePrefix <> hash <> "-" <> name
instance ToString StorePath where
  toString = toString . toText

newtype Host = Host Text deriving newtype (Ord, Eq) deriving stock (Show, Read)
instance ToText Host where
  toText (Host name) = name
instance ToString Host where
  toString = toString . toText

noMatch :: Parser ParseResult
noMatch = NotRecognized <$ takeTill isEndOfLine <* endOfLine

storePath :: Parser StorePath
storePath =
  StorePath
    <$> (string storePrefix *> take 32)
    <*> (char '-' *> takeWhile (inClass "a-zA-Z0-9_.-"))

derivation :: Parser Derivation
derivation = storePath >>= \x -> case stripSuffix ".drv" (name x) of
  Just realName -> pure . Derivation $ x { name = realName }
  Nothing       -> mzero

inTicks :: Parser a -> Parser a
inTicks x = tick *> x <* tick

tick :: Parser ()
tick = () <$ char '\''

noTicks :: Parser Text
noTicks = takeTill (== '\'')

host :: Parser Host
host = Host <$> inTicks noTicks

ellipsisEnd :: Parser ()
ellipsisEnd = string "..." >> endOfLine

indent :: Parser ()
indent = () <$ string "  "

planBuilds :: Parser ParseResult
planBuilds =
  PlanBuilds
    .   fromList
    <$> (  string "these derivations will be built:"
        *> endOfLine
        *> many planBuildLine
        )

planBuildLine :: Parser Derivation
planBuildLine = indent *> derivation <* endOfLine

planDownloads :: Parser ParseResult
planDownloads =
  PlanDownloads
    <$> (string "these paths will be fetched (" *> double)
    <*> (string " MiB download, " *> double)
    <*> (  string " MiB unpacked):"
        *> endOfLine
        *> (fromList <$> many planDownloadLine)
        )

planDownloadLine :: Parser StorePath
planDownloadLine = indent *> storePath <* endOfLine

copying :: Parser ParseResult
copying =
  string "copying "
    *> (   transmission
       <|> (PlanCopies <$> decimal <* string " paths" <* ellipsisEnd)
       )

transmission :: Parser ParseResult
transmission = do
  p <- string "path " *> inTicks storePath
  (Uploading p <$> toHost <|> Downloading p <$> fromHost) <* ellipsisEnd

fromHost :: Parser Host
fromHost = string " from " *> host

toHost :: Parser Host
toHost = string " to " *> host

onHost :: Parser Host
onHost = string " on " *> host

building :: Parser ParseResult
building = do
  p <- string "building " *> inTicks derivation
  LocalBuild p <$ ellipsisEnd <|> RemoteBuild p <$> onHost <* ellipsisEnd
