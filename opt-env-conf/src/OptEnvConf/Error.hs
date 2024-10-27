{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module OptEnvConf.Error where

import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import Data.Map (Map)
import qualified Data.Map as M
import qualified Data.Text as T
import GHC.Stack (SrcLoc)
import OptEnvConf.Doc
import OptEnvConf.Output
import OptEnvConf.Parser
import Text.Colour

data ParseError = ParseError
  { parseErrorSrcLoc :: !(Maybe SrcLoc),
    parseErrorMessage :: !ParseErrorMessage
  }
  deriving (Show)

data ParseErrorMessage
  = ParseErrorEmpty
  | ParseErrorEmptySetting
  | ParseErrorNoReaders
  | ParseErrorCheckFailed !Bool !String
  | ParseErrorMissingArgument !(Maybe OptDoc)
  | ParseErrorArgumentRead !(Maybe OptDoc) !(NonEmpty String)
  | ParseErrorMissingOption !(Maybe OptDoc)
  | ParseErrorOptionRead !(Maybe OptDoc) !(NonEmpty String)
  | ParseErrorMissingEnvVar !(Maybe EnvDoc)
  | ParseErrorEnvRead !(Maybe EnvDoc) !(NonEmpty String)
  | ParseErrorMissingSwitch !(Maybe OptDoc)
  | ParseErrorMissingConfVal !(Maybe ConfDoc)
  | ParseErrorConfigRead !(Maybe ConfDoc) !String
  | ParseErrorMissingCommand ![CommandDoc ()]
  | ParseErrorUnrecognisedCommand !String ![CommandDoc ()]
  | ParseErrorAllOrNothing !(Map SrcLocHash SrcLoc)
  | ParseErrorUnrecognised !(NonEmpty String)
  deriving (Show)

-- | Whether the other side of an 'Alt' should be tried if we find this error.
errorIsForgivable :: ParseError -> Bool
errorIsForgivable = errorMessageIsForgivable . parseErrorMessage

errorMessageIsForgivable :: ParseErrorMessage -> Bool
errorMessageIsForgivable = \case
  ParseErrorEmpty -> True
  ParseErrorEmptySetting -> False
  ParseErrorNoReaders -> False
  ParseErrorCheckFailed forgivable _ -> forgivable
  ParseErrorMissingArgument _ -> True
  ParseErrorArgumentRead _ _ -> False
  ParseErrorMissingSwitch _ -> True
  ParseErrorOptionRead _ _ -> False
  ParseErrorMissingOption _ -> True
  ParseErrorMissingEnvVar _ -> True
  ParseErrorEnvRead _ _ -> False
  ParseErrorMissingConfVal _ -> True
  ParseErrorConfigRead _ _ -> False
  ParseErrorMissingCommand cs -> not $ null cs
  ParseErrorUnrecognisedCommand _ _ -> False
  ParseErrorAllOrNothing _ -> False
  ParseErrorUnrecognised _ -> False

eraseErrorSrcLocs :: (Functor f) => f ParseError -> f ParseError
eraseErrorSrcLocs = fmap eraseErrorSrcLoc

eraseErrorSrcLoc :: ParseError -> ParseError
eraseErrorSrcLoc pe = pe {parseErrorSrcLoc = Nothing}

renderErrors :: NonEmpty ParseError -> [Chunk]
renderErrors = unlinesChunks . concatMap renderError . NE.toList

renderError :: ParseError -> [[Chunk]]
renderError ParseError {..} =
  concat
    [ case parseErrorMessage of
        ParseErrorEmpty ->
          [["Hit the 'empty' case of the Parser type, this should not happen."]]
        ParseErrorEmptySetting ->
          [["This setting has not been configured to be able to parse anything."]]
        ParseErrorNoReaders ->
          [ ["No readers were configured for an argument, option, or env."],
            ["You should not be seeing this error because the linting phase should have caught it."]
          ]
        ParseErrorCheckFailed _ err ->
          [["Check failed: "], [chunk $ T.pack err]]
        ParseErrorMissingArgument o ->
          [ "Missing argument: "
              : unwordsChunks (maybe [] renderOptDocLong o)
          ]
        ParseErrorArgumentRead md errs ->
          ["Failed to read argument: "]
            : unwordsChunks (maybe [] renderOptDocLong md)
            : map (\err -> [chunk $ T.pack err]) (NE.toList errs)
        ParseErrorMissingOption o ->
          ["Missing option: " : unwordsChunks (maybe [] renderOptDocLong o)]
        ParseErrorMissingSwitch o ->
          ["Missing switch: " : unwordsChunks (maybe [] renderOptDocLong o)]
        ParseErrorOptionRead md errs ->
          ["Failed to read option: "]
            : unwordsChunks (maybe [] renderOptDocLong md)
            : map (\err -> [chunk $ T.pack err]) (NE.toList errs)
        ParseErrorMissingEnvVar md ->
          ["Missing env var: "]
            : maybe [] renderEnvDoc md
        ParseErrorEnvRead md errs ->
          ["Failed to read env var: "]
            : maybe [] renderEnvDoc md
            ++ map (\err -> [chunk $ T.pack err]) (NE.toList errs)
        ParseErrorMissingConfVal md ->
          ["Missing config value: "] : maybe [] renderConfDoc md
        ParseErrorConfigRead md s ->
          ["Failed to parse configuration: "]
            : maybe [] renderConfDoc md
            ++ [[chunk $ T.pack s]]
        ParseErrorMissingCommand cs ->
          ["Missing command, available commands:"]
            : availableCommandsLines cs
        ParseErrorUnrecognisedCommand c cs ->
          [ [fore red "Unrecognised command: ", fore yellow $ chunk (T.pack c)],
            [fore blue "available commands:"]
          ]
            ++ availableCommandsLines cs
        ParseErrorAllOrNothing locs ->
          [ ["You are seeing this error because at least one, but not all, of the settings in an allOrNothing (or subSettings) parser have been defined."],
            ["The following settings have been parsed:"]
          ]
            ++ map (pure . srcLocChunk) (M.elems locs)
        ParseErrorUnrecognised leftovers ->
          ["Unrecognised args: " : unwordsChunks (map (pure . chunk . T.pack) (NE.toList leftovers))],
      maybe [] (pure . ("see " :) . pure . srcLocChunk) parseErrorSrcLoc
    ]

availableCommandsLines :: [CommandDoc a] -> [[Chunk]]
availableCommandsLines = map $ \CommandDoc {..} ->
  [ commandChunk commandDocArgument,
    ": ",
    helpChunk commandDocHelp
  ]
