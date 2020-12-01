module AdvSearch.Range exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Array
import Lib.Ffi as Ffi
import Gen.Types as GT
import AdvSearch.Lib exposing (..)


type alias Model a =
  { op  : Op
  , val : Int
  , unk : Bool
  , lst : Array.Array a
  }


type Msg
  = MOp Op
  | Val String
  | Unknown Bool


update : Msg -> Model a -> Model a
update msg model =
  case msg of
    MOp o -> { model | op = o }
    Val n -> { model | val = Maybe.withDefault 0 (String.toInt n) }
    Unknown b -> { model | unk = b, op = if b && model.op /= Ne && model.op /= Eq then Eq else model.op }

fromQuery : (Data, Model comparable) -> Op -> comparable -> Maybe (Data, Model comparable)
fromQuery (dat,m) op v = Array.foldl (\v2 (i,r) -> (i+1, if v2 == v then Just i else r)) (0,Nothing) m.lst |> Tuple.second |> Maybe.map (\i -> (dat,{ m | val = i, op = op, unk = False }))

fromQueryUnk : (Data, Model comparable) -> Op -> Maybe (Data, Model comparable)
fromQueryUnk (dat,m) op = Just (dat, { m | unk = True, op = if op == Eq then Eq else Ne })

toQuery : (Op -> a -> Query) -> (Op -> String -> Query) -> Model a -> Maybe Query
toQuery k u m = if m.unk then Just (u m.op "") else Array.get m.val m.lst |> Maybe.map (\v -> k m.op v)

view : Bool -> String -> (a -> String) -> Model a -> (Html Msg, () -> List (Html Msg))
view canUnk lbl fmt model =
  let val n = Array.get n model.lst |> Maybe.map fmt |> Maybe.withDefault ""
  in
  ( span [ class "nowrap" ] [ text <| lbl ++ " " ++ showOp model.op ++ " " ++ if model.unk then "Unknown" else val model.val ]
  , \() ->
    [ div [ class "advheader", style "width" "290px" ]
      [ h3 [] [ text lbl ]
      , div [ class "opts" ]
        [ inputOp model.unk model.op MOp
        , if canUnk then linkRadio model.unk Unknown [text "Unknown"] else text ""
        ]
      ]
    , if model.unk
      then p [ class "center" ] [ text <| lbl ++ " is " ++ (if model.op /= Eq then "known/set." else "unknown/unset.") ]
      else
      div [ style "display" "flex", style "justify-content" "space-between", style "margin-top" "5px" ]
      [ b [ class "grayedout" ] [ text (val 0) ]
      , b [] [ text (val model.val) ]
      , b [ class "grayedout" ] [ text (val (Array.length model.lst - 1)) ]
      ]
    , if model.unk then text "" else
      input
      [ type_ "range"
      , Html.Attributes.min "0"
      , Html.Attributes.max (String.fromInt (Array.length model.lst - 1))
      , value (String.fromInt model.val)
      , onInput Val
      , style "width" "290px"
      ] []
    ]
  )




heightInit dat = (dat, { op = Ge, val = 150, unk = False, lst = Array.initialize 300 (\n -> n+1) })

heightFromQuery d q =
  case q of
    QInt 6 op v -> fromQuery (heightInit d) op v
    QStr 6 op "" -> fromQueryUnk (heightInit d) op
    _ -> Nothing

heightView = view True "Height" (\v -> String.fromInt v ++ "cm")




weightInit dat = (dat, { op= Ge, val = 60, unk = False, lst = Array.initialize 401 identity })

weightFromQuery d q =
  case q of
    QInt 7 op v -> fromQuery (weightInit d) op v
    QStr 7 op "" -> fromQueryUnk (weightInit d) op
    _ -> Nothing

weightView = view True "Weight" (\v -> String.fromInt v ++ "kg")




bustInit dat = (dat, { op = Ge, val = 40, unk = False, lst = Array.initialize 101 (\n -> n+20) })

bustFromQuery d q =
  case q of
    QInt 8 op v -> fromQuery (bustInit d) op v
    QStr 8 op "" -> fromQueryUnk (bustInit d) op
    _ -> Nothing

bustView = view True "Bust" (\v -> String.fromInt v ++ "cm")




waistInit dat = (dat, { op = Ge, val = 40, unk = False, lst = Array.initialize 101 (\n -> n+20) })

waistFromQuery d q =
  case q of
    QInt 9 op v -> fromQuery (waistInit d) op v
    QStr 9 op "" -> fromQueryUnk (waistInit d) op
    _ -> Nothing

waistView = view True "Waist" (\v -> String.fromInt v ++ "cm")




hipsInit dat = (dat, { op = Ge, val = 40, unk = False, lst = Array.initialize 101 (\n -> n+20) })

hipsFromQuery d q =
  case q of
    QInt 10 op v -> fromQuery (hipsInit d) op v
    QStr 10 op "" -> fromQueryUnk (hipsInit d) op
    _ -> Nothing

hipsView = view True "Hips" (\v -> String.fromInt v ++ "cm")




cupInit dat = (dat, { op = Ge, val = 3, unk = False, lst = Array.fromList (List.map Tuple.first (List.drop 1 GT.cupSizes)) })

cupFromQuery d q =
  case q of
    QStr 11 op "" -> fromQueryUnk (cupInit d) op
    QStr 11 op v -> fromQuery (cupInit d) op v
    _ -> Nothing

cupView = view True "Cup size" identity




ageInit dat = (dat, { op = Ge, val = 17, unk = False, lst = Array.initialize 121 identity })

ageFromQuery d q =
  case q of
    QInt 12 op v  -> fromQuery (ageInit d) op v
    QStr 12 op "" -> fromQueryUnk (ageInit d) op
    _ -> Nothing

ageView = view True "Age" (\v -> if v == 1 then "1 year" else String.fromInt v ++ " years")




popularityInit dat = (dat, { op = Ge, val = 10, unk = False, lst = Array.initialize 101 identity })

popularityFromQuery d q =
  case q of
    QInt 9 op v -> fromQuery (popularityInit d) op v
    _ -> Nothing

popularityView = view False "Popularity" String.fromInt




ratingInit dat = (dat, { op = Ge, val = 40, unk = False, lst = Array.initialize 91 (\v -> v+10) })

ratingFromQuery d q =
  case q of
    QInt 10 op v -> fromQuery (ratingInit d) op v
    _ -> Nothing

ratingView = view False "Rating" (\v -> Ffi.fmtFloat (toFloat v / 10) 1)




votecountInit dat = (dat, { op = Ge, val = 10, unk = False, lst = Array.fromList [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 2000, 3000, 4000, 5000 ] })

votecountFromQuery d q =
  case q of
    QInt 11 op v -> fromQuery (votecountInit d) op v
    _ -> Nothing

votecountView = view False "# Votes" String.fromInt
