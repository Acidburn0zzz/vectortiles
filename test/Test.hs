{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE TypeApplications #-}

module Main where

import qualified Data.ByteString as BS
import           Data.Hex
import           Data.ProtocolBuffers
import           Data.Serialize.Get
import           Data.Serialize.Put
import qualified Geography.VectorTile.Protobuf as R
import           Test.Tasty
import           Test.Tasty.HUnit
import           Geography.VectorTile
import           Geography.VectorTile.Geometry
import qualified Data.Vector.Unboxed as U

---

main :: IO ()
main = do
  op <- BS.readFile "test/onepoint.mvt"
  ls <- BS.readFile "test/linestring.mvt"
  pl <- BS.readFile "test/polygon.mvt"
  rd <- BS.readFile "test/roads.mvt"
  defaultMain $ suite op ls pl rd

{- SUITES -}

suite :: BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString -> TestTree
suite op ls pl rd = testGroup "Unit Tests"
  [ testGroup "Protobuf"
    [ testGroup "Decoding"
      [ testCase "onepoint.mvt -> Raw.Tile" $ testOnePoint op
      , testCase "linestring.mvt -> Raw.Tile" $ testLineString ls
      , testCase "polygon.mvt -> Raw.Tile" $ testPolygon pl
      , testCase "roads.mvt -> Raw.Tile" $ testDecode rd
      , testCase "onepoint.mvt -> VectorTile" $ tileDecode op
      , testCase "linestring.mvt -> VectorTile" $ tileDecode ls
      , testCase "polygon.mvt -> VectorTile" $ tileDecode pl
      , testCase "roads.mvt -> VectorTile" $ tileDecode rd
      ]
    , testGroup "Encoding"
      [ testGroup "RawVectorTile <-> VectorTile"
        [ testCase "One Point" $ encodeIso onePoint
        , testCase "One LineString" $ encodeIso oneLineString
        , testCase "One Polygon" $ encodeIso onePolygon
        , testCase "roads.mvt" . encodeIso . fromRight $ R.decode rd
        ]
      ]
    , testGroup "Serialization Isomorphism"
      [ --testCase "onepoint.mvt <-> Raw.Tile" $ fromRaw op
--      , testCase "linestring.mvt <-> Raw.Tile" $ fromRaw ls
--      , testCase "polygon.mvt <-> Raw.Tile" $ fromRaw pl
      --    , testCase "roads.mvt <-> Raw.Tile" $ fromRaw rd
      testCase "testTile <-> protobuf bytes" testTileIso
      ]
    ]
  , testGroup "Geometries"
    [ testCase "Z-encoding Isomorphism" zencoding
    , testCase "Command Parsing" commandTest
    , testCase "[Word32] <-> [Command]" commandIso
    , testCase "[Word32] <-> V.Vector Point" pointIso
    , testCase "[Word32] <-> V.Vector LineString" linestringIso
    , testCase "[Word32] <-> V.Vector Polygon (2 ex)" polygonIso
    , testCase "[Word32] <-> V.Vector Polygon (1 ex, 1 in)" polygonIso2
    ]
  ]

testOnePoint :: BS.ByteString -> Assertion
testOnePoint vt = case decodeIt vt of
                    Left e -> assertFailure e
                    Right t -> t @?= onePoint

testLineString :: BS.ByteString -> Assertion
testLineString vt = case decodeIt vt of
                      Left e -> assertFailure e
                      Right t -> t @?= oneLineString

testPolygon :: BS.ByteString -> Assertion
testPolygon vt = case decodeIt vt of
                   Left e -> assertFailure e
                   Right t -> t @?= onePolygon

-- | For testing is decoding succeeded in generally. Makes no guarantee
-- about the quality of the content, only that the parse succeeded.
testDecode :: BS.ByteString -> Assertion
testDecode = assert . isRight . decodeIt

tileDecode :: BS.ByteString -> Assertion
tileDecode bs = case decodeIt bs of
  Left e -> assertFailure e
  Right t -> assert . isRight $ R.tile t

fromRaw :: BS.ByteString -> Assertion
fromRaw vt = case decodeIt vt of
               Left e -> assertFailure e
               Right l -> hex (encodeIt l) @?= hex vt
--               Right l -> if runPut (encodeMessage l) == vt
--                          then assert True
--                          else assertString "Isomorphism failed."

testTileIso :: Assertion
testTileIso = case decodeIt pb of
                 Right tl -> assertEqual "" tl testTile
                 Left e -> assertFailure e
  where pb = encodeIt testTile

decodeIt :: BS.ByteString -> Either String R.RawVectorTile
decodeIt = runGet decodeMessage

encodeIt :: R.RawVectorTile -> BS.ByteString
encodeIt = runPut . encodeMessage

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _ = False

fromRight :: Either a b -> b
fromRight (Right b) = b
fromRight _ = error "`Left` given to fromRight!"

rawTest :: IO (Either String R.RawVectorTile)
rawTest = decodeIt <$> BS.readFile "onepoint.mvt"

encodeIso :: R.RawVectorTile -> Assertion
encodeIso vt = assert . isRight . fmap R.untile $ R.tile vt

testTile :: R.RawVectorTile
testTile = R.RawVectorTile $ putField [l]
  where l = R.RawLayer { R._version = putField 2
                       , R._name = putField "testlayer"
                       , R._features = putField [f]
                       , R._keys = putField ["somekey"]
                       , R._values = putField [v]
                       , R._extent = putField $ Just 4096
                       }
        f = R.RawFeature { R._featureId = putField $ Just 0
                         , R._tags = putField [0,0]
                         , R._geom = putField $ Just R.Point
                         , R._geometries = putField [9, 50, 34]  -- MoveTo(+25,+17)
                         }
        v = R.RawVal { R._string = putField $ Just "Some Value"
                     , R._float = putField Nothing
                     , R._double = putField Nothing
                     , R._int64 = putField Nothing
                     , R._uint64 = putField Nothing
                     , R._sint = putField Nothing
                     , R._bool = putField Nothing
                     }

-- | Correct decoding of `onepoint.mvt`
onePoint :: R.RawVectorTile
onePoint = R.RawVectorTile $ putField [l]
  where l = R.RawLayer { R._version = putField 1
                       , R._name = putField "OnePoint"
                       , R._features = putField [f]
                       , R._keys = putField []
                       , R._values = putField []
                       , R._extent = putField $ Just 4096
                       }
        f = R.RawFeature { R._featureId = putField Nothing
                         , R._tags = putField []
                         , R._geom = putField $ Just R.Point
                         , R._geometries = putField [9, 10, 10]  -- MoveTo(+5,+5)
                         }

-- | Correct decoding of `linestring.mvt`
oneLineString :: R.RawVectorTile
oneLineString = R.RawVectorTile $ putField [l]
  where l = R.RawLayer { R._version = putField 1
                       , R._name = putField "OneLineString"
                       , R._features = putField [f]
                       , R._keys = putField []
                       , R._values = putField []
                       , R._extent = putField $ Just 4096
                       }
        f = R.RawFeature { R._featureId = putField Nothing
                         , R._tags = putField []
                         , R._geom = putField $ Just R.LineString
                         -- MoveTo(+5,+5), LineTo(+1195,+1195)
                         , R._geometries = putField [9, 10, 10, 10, 2390, 2390]
                         }

-- | Correct decoding of `polygon.mvt`
onePolygon :: R.RawVectorTile
onePolygon = R.RawVectorTile $ putField [l]
  where l = R.RawLayer { R._version = putField 1
                       , R._name = putField "OnePolygon"
                       , R._features = putField [f]
                       , R._keys = putField []
                       , R._values = putField []
                       , R._extent = putField $ Just 4096
                       }
        f = R.RawFeature { R._featureId = putField Nothing
                         , R._tags = putField []
                         , R._geom = putField $ Just R.Polygon
                         -- MoveTo(+2,+2), LineTo(+3,+2), LineTo(-3,+2), ClosePath
                         , R._geometries = putField [9, 4, 4, 18, 6, 4, 5, 4, 15]
                         }

zencoding :: Assertion
zencoding = assert $ map (R.unzig . R.zig) vs @?= vs
  where vs = [0,(-1),1,(-2),2,(-3),3,2147483647,(-2147483648)]

commandTest :: Assertion
commandTest = assert $ R.commands [9,4,4,18,6,4,5,4,15] @?= Right
  [ R.MoveTo $ U.singleton (2,2)
  , R.LineTo $ U.fromList [(3,2),(-3,2)]
  , R.ClosePath ]

commandIso :: Assertion
commandIso = assert $ (R.uncommands . fromRight $ R.commands cs) @?= cs
  where cs = [9,4,4,18,6,4,5,4,15]

pointIso :: Assertion
pointIso = cs' @?= cs
  where cs = [25,4,4,6,6,3,3]
        cs' = fromRight $ R.uncommands . R.toCommands <$> (R.commands cs >>= R.fromCommands @Point)

linestringIso :: Assertion
linestringIso = cs' @?= cs
  where cs = [9,4,4,18,6,4,5,4,9,4,4,18,6,4,5,4]
        cs' = fromRight $ R.uncommands . R.toCommands <$> (R.commands cs >>= R.fromCommands @LineString)

-- | Two external rings
polygonIso :: Assertion
polygonIso = cs' @?= cs
  where cs = [9,4,4,18,6,4,5,4,15,9,4,4,18,6,4,5,4,15]
        cs' = fromRight $ R.uncommands . R.toCommands <$> (R.commands cs >>= R.fromCommands @Polygon)

-- | One external, one internal
polygonIso2 :: Assertion
polygonIso2 = cs' @?= cs
  where cs = [9,4,4,26,6,0,0,6,5,0,15,9,2,3,26,0,2,2,0,0,1,15]
        cs' = fromRight $ R.uncommands . R.toCommands <$> (R.commands cs >>= R.fromCommands @Polygon)

{-}
foo :: FilePath -> IO (Either Text VectorTile)
foo bs = do
  mvt <- BS.readFile bs
  pure $ R.decode mvt >>= tile

-- fmap (V.length . layers <$>) $ foo "roads.mvt"
-}
