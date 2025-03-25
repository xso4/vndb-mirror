module Lib.Util exposing (..)

import Task
import Process
import Gen.Types as GT

-- Delete an element from a List
delidx : Int -> List a -> List a
delidx n l = List.take n l ++ List.drop (n+1) l


-- Modify an element in a List
modidx : Int -> (a -> a) -> List a -> List a
modidx n f = List.indexedMap (\i e -> if i == n then f e else e)


-- Haskell's 'lookup' - find an entry in an association list
lookup : a -> List (a,b) -> Maybe b
lookup n l = List.filter (\(a,_) -> a == n) l |> List.head |> Maybe.map Tuple.second


-- Have to use Process.sleep instead of Task.succeed here, otherwise any
-- subscriptions are not updated.
selfCmd : msg -> Cmd msg
selfCmd m = Task.perform (always m) (Process.sleep 1.0)


vndbidNum : String -> Int
vndbidNum = String.dropLeft 1 >> String.toInt >> Maybe.withDefault 0


vndbid : Char -> Int -> String
vndbid c n = String.fromChar c ++ String.fromInt n



-- List of script-languages (i.e. not the generic "Chinese" option), with JA and EN ordered first.
scriptLangs : List (String, String)
scriptLangs =
     (List.filter (\(l,_) -> l == "ja") GT.languages)
  ++ (List.filter (\(l,_) -> l == "en") GT.languages)
  ++ (List.filter (\(l,_) -> l /= "zh" && l /= "en" && l /= "ja") GT.languages)

-- "Location languages", i.e. generic language without script indicator, again with JA and EN ordered first.
locLangs : List (String, String)
locLangs =
     (List.filter (\(l,_) -> l == "ja") GT.languages)
  ++ (List.filter (\(l,_) -> l == "en") GT.languages)
  ++ (List.filter (\(l,_) -> l /= "zh-Hans" && l /= "zh-Hant" && l /= "en" && l /= "ja") GT.languages)


-- Format a release resolution, first argument indicates whether empty string is to be used for "unknown"
resoFmt : Bool -> Int -> Int -> String
resoFmt empty x y =
  case (x,y) of
    (0,0) -> if empty then "" else "Unknown"
    (0,1) -> "Non-standard"
    _ -> String.fromInt x ++ "x" ++ String.fromInt y

-- Inverse of resoFmt
resoParse : Bool -> String -> Maybe (Int, Int)
resoParse empty s =
  let t =  String.replace "*" "x" s
        |> String.replace "×" "x"
        |> String.replace " " ""
        |> String.replace "\t" ""
        |> String.toLower |> String.trim
  in
  case (t, String.split "x" t) of
    ("", _) -> if empty then Just (0,0) else Nothing
    ("unknown", _) -> Just (0,0)
    ("non-standard", _) -> Just (0,1)
    (_, [sx,sy]) ->
      case (String.toInt sx, String.toInt sy) of
        (Just ix, Just iy) -> if ix < 1 || ix > 32767 || iy < 1 || iy > 32767 then Nothing else Just (ix,iy)
        _ -> Nothing
    _ -> Nothing
