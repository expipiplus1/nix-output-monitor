module Main where
import           Prelude                        ( )
import           Relude
import           Test.HUnit
import           Parser
import           Data.Text.Lazy.IO             as LTextIO
import           System.Process
import           Data.Time
import           IO
import           Update                         ( initalState
                                                , updateState
                                                , BuildState(startTime)
                                                )
import           Relude.Unsafe


main :: IO ()
main = do
  counts <- runTestTT $ test
    [ "Golden 1" ~: do
        -- First we ensure that the necessary derivations exist in the store
        callProcess "nix-build" ["test/golden1.nix", "--no-out-link"]
        now           <- getCurrentTime
        log           <- LTextIO.readFile "test/golden1.log"
        endState <- processText parser (initalState now) updateState Nothing log
        expectedState <- read . toString <$> LTextIO.readFile
          "test/golden1.state"
        assertEqual "State matches"
                    expectedState
                    endState { startTime = read "2020-10-03 12:54:17.029638514 UTC" }
    ]
  if errors counts + failures counts == 0 then exitSuccess else exitFailure
