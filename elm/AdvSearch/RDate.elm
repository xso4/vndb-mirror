module AdvSearch.RDate exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Lib.Html exposing (..)
import Lib.RDate as R
import AdvSearch.Query exposing (..)


type alias Model =
  { op    : Op
  , fuzzy : Bool
  , date  : R.RDate
  }


type Msg
  = MOp Op
  | Fuzzy Bool
  | Date R.RDate


onlyEq : Int -> Bool
onlyEq d = d == 99999999 || d == 0


update : Msg -> Model -> Model
update msg model =
  case msg of
    MOp o   -> { model | op = o }
    Fuzzy f -> { model | fuzzy = f }
    Date d  -> { model | op = if onlyEq d && model.op /= Eq && model.op /= Ne then Eq else model.op, date = d }


init : Data -> (Data, Model)
init dat = (dat,
  { op    = Le
  , fuzzy = True
  , date  = 1
  })


toQuery : Model -> Maybe Query
toQuery model = Just <|
  let f o date = QInt 7 o date
      e = R.expand model.date
      ystart = R.compact { y=e.y, m=  1, d= 1 }
      mstart = R.compact { y=e.y, m=e.m, d= 1 }
  in
  if not model.fuzzy || e.y == 0 || e.y == 9999 then f model.op model.date else
  case (model.op, e.m, e.d) of
    -- Fuzzy (in)equality turns into a date range
    (Eq, 99, 99) -> QAnd [ f Ge ystart, f Le model.date ]
    (Eq,  _, 99) -> QAnd [ f Ge mstart, f Le model.date ]
    (Ne, 99, 99) -> QOr  [ f Lt ystart, f Gt model.date ]
    (Ne,  _, 99) -> QOr  [ f Lt mstart, f Gt model.date ]
    -- Fuzzy Ge and Lt just need the date adjusted to the correct boundary
    (Ge, 99, 99) -> f Ge ystart
    (Ge,  _, 99) -> f Ge mstart
    (Lt, 99, 99) -> f Lt ystart
    (Lt,  _, 99) -> f Lt mstart
    _ -> f model.op model.date


fromQuery : Data -> Query -> Maybe (Data, Model)
fromQuery dat q =
  let m op fuzzy date = Just (dat, { op = op, fuzzy = fuzzy, date = date })
      fuzzyNeq op start end =
        let se = R.expand start
            ee = R.expand end
        in  if se.y == ee.y && (ee.m < 99 || se.m == 1) && se.d == 1 && ee.d == 99 then m op True end else Nothing
      canFuzzy o e = e.y == 0 || e.y == 9999 || e.d /= 99 || o == Gt || o == Le
  in
  case q of
    QAnd [QInt 7 Ge start, QInt 7 Le end] -> fuzzyNeq Eq start end
    QOr  [QInt 7 Lt start, QInt 7 Gt end] -> fuzzyNeq Ne start end
    QInt 7 o v -> m o (canFuzzy o (R.expand v)) v
    _ -> Nothing


view : Model -> (Html Msg, () -> List (Html Msg))
view model =
  ( text <| showOp model.op ++ " " ++ R.format (R.expand model.date)
  , \() ->
    [ div [ class "advheader", style "width" "290px" ]
      [ h3 [] [ text "Release date" ]
      , div [ class "opts" ]
        [ inputOp (onlyEq model.date) model.op MOp
        , if (R.expand model.date).d /= 99 || model.date == 99999999 then text "" else
          linkRadio model.fuzzy Fuzzy [ span [ title
            <| "Without fuzzy matching, partial dates will always match after the last date of the chosen time period, "
            ++ "e.g. \"< 2010-10\" would also match anything released in 2010-10 and \"= 2010-10\" would only match releases for which we don't know the exact date."
            ++ "\n\nFuzzy match will adjust the query to do what you mean."
          ] [ text "fuzzy" ] ]
        ]
      ]
    , R.view model.date True True Date
    ]
  )
