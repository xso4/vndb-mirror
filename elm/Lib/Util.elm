module Lib.Util exposing (..)

import Dict
import Task
import Regex
import Lib.Ffi as Ffi

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
        Just m -> if Dict.member e m then Nothing else Just (Dict.insert e True m)
  in
    case List.foldr step (Just Dict.empty) l of
      Nothing -> True
      Just _  -> False


-- Haskell's 'lookup' - find an entry in an association list
lookup : a -> List (a,b) -> Maybe b
lookup n l = List.filter (\(a,_) -> a == n) l |> List.head |> Maybe.map Tuple.second


selfCmd : msg -> Cmd msg
selfCmd m = Task.perform (always m) (Task.succeed True)


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
nonlatin_ = Maybe.withDefault Regex.never (Regex.fromString "[\\u3000-\\u9fff\\uff00-\\uff9f\\u0400-\\u04ff\\u1100-\\u11ff\\uac00-\\ud7af]")

-- This regex can't differentiate between Japanese and Chinese, so has a good chance of returning true for Chinese as well.
containsJapanese : String -> Bool
containsJapanese = Regex.contains jap_

containsNonLatin : String -> Bool
containsNonLatin = Regex.contains nonlatin_


-- Given an email address, returns the name of the provider if it has a good chance of blocking mails from our server.
shittyMailProvider : String -> Maybe String
shittyMailProvider s =
  case String.split "@" s |> List.drop 1 |> List.head |> Maybe.withDefault "" |> String.toLower of
    "sbcglobal.net" -> Just "AT&T"
    "att.net"       -> Just "AT&T"
    _ -> Nothing


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
