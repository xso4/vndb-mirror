module Lib.Util exposing (..)

import Set
import Task
import Process
import Regex
import Lib.Ffi as Ffi
import Gen.Api as GApi
import Gen.Types as GT

-- Delete an element from a List
delidx : Int -> List a -> List a
delidx n l = List.take n l ++ List.drop (n+1) l


-- Modify an element in a List
modidx : Int -> (a -> a) -> List a -> List a
modidx n f = List.indexedMap (\i e -> if i == n then f e else e)


isJust : Maybe a -> Bool
isJust m = case m of
  Just _ -> True
  _      -> False


-- Returns true if the list contains duplicates
hasDuplicates : List comparable -> Bool
hasDuplicates l =
  let
    step e acc =
      case acc of
        Nothing -> Nothing
        Just m -> if Set.member e m then Nothing else Just (Set.insert e m)
  in
    case List.foldr step (Just Set.empty) l of
      Nothing -> True
      Just _  -> False


-- Returns true if list a contains elements also in list b
contains : List comparable -> List comparable -> Bool
contains a b =
  let d = Set.fromList b
  in List.any (\e -> Set.member e d) a


-- Haskell's 'lookup' - find an entry in an association list
lookup : a -> List (a,b) -> Maybe b
lookup n l = List.filter (\(a,_) -> a == n) l |> List.head |> Maybe.map Tuple.second


-- Have to use Process.sleep instead of Task.succeed here, otherwise any
-- subscriptions are not updated.
selfCmd : msg -> Cmd msg
selfCmd m = Task.perform (always m) (Process.sleep 1.0)


-- Based on VNDBUtil::gtintype()
validateGtin : String -> Bool
validateGtin =
  let check = String.fromInt
        >> String.reverse
        >> String.toList
        >> List.indexedMap (\i c -> (Char.toCode c - Char.toCode '0') * if modBy 2 i == 0 then 1 else 3)
        >> List.sum
      inval n =
            n <     1000000000
        || (n >=  200000000000 && n <  600000000000)
        || (n >= 2000000000000 && n < 3000000000000)
        ||  n >= 9770000000000
        || modBy 10 (check n) /= 0
  in String.filter Char.isDigit >> String.toInt >> Maybe.map (not << inval) >> Maybe.withDefault False


-- Convert an image ID (e.g. "sf500") into a URL.
imageUrl : String -> String
imageUrl id =
  let num = String.dropLeft 2 id |> String.toInt |> Maybe.withDefault 0
  in Ffi.urlStatic ++ "/" ++ String.left 2 id ++ "/" ++ String.fromInt (modBy 10 (num // 10)) ++ String.fromInt (modBy 10 num) ++ "/" ++ String.fromInt num ++ ".jpg"


vndbidNum : String -> Int
vndbidNum = String.dropLeft 1 >> String.toInt >> Maybe.withDefault 0


vndbid : Char -> Int -> String
vndbid c n = String.fromChar c ++ String.fromInt n


jap_ : Regex.Regex
jap_ = Maybe.withDefault Regex.never (Regex.fromString "[\\u3000-\\u9fff\\uff00-\\uff9f]")

-- Not even close to comprehensive, just excludes a few scripts commonly found on VNDB.
nonlatin_ : Regex.Regex
nonlatin_ = Maybe.withDefault Regex.never (Regex.fromString "[[\\u0400-\\u04ff\\u0600-\\u06ff\\u0e00-\\u0e7f\\u1100-\\u11ff\\u1400-\\u167f\\u3040-\\u3099\\u30a1-\\u30fa\\u3100-\\u9fff\\uac00-\\ud7af\\uff66-\\uffdc]]")

-- This regex can't differentiate between Japanese and Chinese, so has a good chance of returning true for Chinese as well.
containsJapanese : String -> Bool
containsJapanese = Regex.contains jap_

containsNonLatin : String -> Bool
containsNonLatin = Regex.contains nonlatin_


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
