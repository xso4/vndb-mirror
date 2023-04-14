module Lib.ExtLinks exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Regex
import Lib.Html exposing (..)
import Gen.ReleaseEdit as GRE
import Gen.ExtLinks as GEL


-- Takes a printf-style string with a single %s or %d formatting code and a parameter to format.
-- Supports 0-padding with '%0<num>d' formatting codes, where <num> <= 99.
-- Returns (prefix, formatted_param, suffix)
-- (This is super ugly and probably better written with elm/parser, but it gets the job done)
splitPrintf : String -> String -> (String, String, String)
splitPrintf s p =
  case String.split "%" s of
    [ pre, suf ] ->
      case String.uncons suf of
        Just ('s', suf1) -> (pre, p, suf1)
        Just ('d', suf1) -> (pre, p, suf1)
        Just ('0', suf1) ->
          case String.uncons suf1 of
            Just (c2, suf2) ->
              case String.uncons suf2 of
                Just ('d', suf3) -> (pre, String.padLeft (Char.toCode c2 - 48) '0' p, suf3)
                Just (c3, suf3) ->
                  case String.uncons suf3 of
                    Just ('d', suf4) ->  (pre, String.padLeft (10*(Char.toCode c2 - 48) + Char.toCode c3 - 48) '0' p, suf4)
                    _ -> (pre, "%", suf)
                _ -> (pre, "%", suf)
            _ -> (pre, "%", suf)
        _ -> (pre, "%", suf)
    _ -> (s, "", "")


type Rec a
  = Unrecognized
  | Duplicate
  | Add (GEL.Site a, String) -- Site, value


type alias Model a =
  { links : a
  , sites : List (GEL.Site a)
  , input : String
  , rec   : Rec a
  , lst   : Bool
  }


type Msg a
  = Del (Int -> a -> a) Int
  | Input String
  | Enter
  | Expand


new : a -> List (GEL.Site a) -> Model a
new l s =
  { links = l
  , sites = s
  , input = ""
  , rec   = Unrecognized
  , lst   = False
  }


update : Msg a -> Model a -> Model a
update msg model =
  let
    match s m = (s, List.map (Maybe.withDefault "") m.submatches |> List.filter (\a -> a /= "") |> List.head |> Maybe.withDefault "")
    fmtval s v = let (_, val, _) = splitPrintf s.fmt v in val
    dup s val = List.filter (\l -> fmtval s l == fmtval s val) (s.links model.links) |> List.isEmpty |> not
    find i =
      case List.concatMap (\s -> List.map (match s) (Regex.find s.regex i)) model.sites |> List.head of
        Nothing -> Unrecognized
        Just (s, val) -> if dup s val then Duplicate else Add (s, val)
    add s val = { model | input = "", rec = Unrecognized, links = s.add val model.links }

  in case msg of
    Del f i -> { model | links = f i model.links }
    Input i ->
      case find (String.trim i) of
        Add (s, val) ->
          if s.multi || List.isEmpty (s.links model.links)
          then add s val
          else { model | input = i, rec = Add (s, val) }
        x ->   { model | input = i, rec = x }
    Enter   ->
      case model.rec of
        Add (s, val) -> add s val
        _ -> model
    Expand  -> { model | lst = not model.lst }


view : Model a -> Html (Msg a)
view model =
  let msg st s = span [] [ br [] [], small [] [ text ">>> " ], if st then b [ class "standout" ] [ text s ] else text s ]
  in
  Html.form [ onSubmit Enter ]
  [ table [] <| List.concatMap (\s ->
      List.indexedMap (\i l ->
        let (pre, val, suf) = splitPrintf s.fmt l
        in tr []
           [ td [] [ a [ href <| pre ++ val ++ suf, target "_blank" ] [ text s.name ] ]
           , td [] [ small [] [ text pre ], text val, small [] [ text suf ] ]
           , td [] [ inputButton "remove" (Del s.del i) [] ]
           ]
      ) (s.links model.links)
    ) model.sites
  , inputText "" model.input Input [style "width" "500px", placeholder "Add URL..."]
  , case (model.input, model.rec) of
      ("", _)           -> text ""
      (_, Unrecognized) -> msg True "Invalid or unrecognized URL."
      (_, Duplicate)    -> msg True "URL is already listed."
      (_, Add (s, _))   -> span [] [ inputButton "Edit" Enter [], msg False <| "URL recognized as: " ++ s.name ]
  , div [ style "margin-top" "5px" ]
    [ span [ onClickD Expand, style "cursor" "pointer" ] [ text <| if model.lst then "▾ " else "▸ ", text "Recognized sites: " ]
    , if model.lst
      then table [] <| List.map (\s ->
        tr []
           [ td [] [ text s.name ]
           , td [] <| List.indexedMap (\i l -> if modBy 2 i == 0 then small [] [ text l ] else text l) s.patt
           ]
        ) model.sites
      else text <| String.join ", " (List.map (\s -> s.name) model.sites) ++ "."
    ]
  ]
