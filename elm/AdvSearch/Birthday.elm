module AdvSearch.Birthday exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Lib.Html exposing (..)
import Lib.RDate as RDate
import AdvSearch.Lib exposing (..)


type alias Model =
  { op    : Op
  , month : Int
  , day   : Int
  }


type Msg
  = MOp Op
  | Month Int
  | Day Int


update : Msg -> Model -> Model
update msg model =
  case msg of
    MOp o   -> { model | op = o }
    Month m -> { model | month = m, day = if m == 0 then 0 else model.day }
    Day d   -> { model | day = d }


init : Data -> (Data, Model)
init dat = (dat,
  { op    = Eq
  , month = 0
  , day   = 0
  })



toQuery : Model -> Maybe Query
toQuery model = Just <| QTuple 14 model.op model.month model.day


fromQuery : Data -> Query -> Maybe (Data, Model)
fromQuery dat q =
  case q of
    QTuple 14 o m d -> Just (dat, { op = o, month = m, day = d })
    _ -> Nothing


view : Model -> (Html Msg, () -> List (Html Msg))
view model =
  ( text <| showOp model.op ++ " "
      ++ (if model.month == 0 then "Unknown"
          else List.drop (model.month-1) RDate.monthList |> List.head |> Maybe.withDefault "")
      ++ (if model.day == 0 then "" else " " ++ String.fromInt model.day)
  , \() ->
    [ div [ class "advheader", style "width" "290px" ]
      [ h3 [] [ text "Birthday" ]
      , div [ class "opts" ] [ inputOp True model.op MOp ]
      ]
    , inputSelect "" model.month Month [style "width" "128px"] <| (0, "Unknown") :: RDate.monthSelect
    , if model.month == 0 then text ""
      else inputSelect "" model.day Day [style "width" "70px"]
        <| (0, "- day -") :: List.map (\i -> (i, String.fromInt i)) (List.range 1 31)
    ]
  )
