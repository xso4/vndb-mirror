module AdvSearch.Resolution exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import AdvSearch.Lib exposing (..)


type alias Model =
  { op     : Op
  , reso   : Maybe (Int,Int)
  , value  : String
  , aspect : Bool
  }


type Msg
  = MOp Op
  | Reso String
  | Aspect Bool


onlyEq : Maybe (Int,Int) -> Bool
onlyEq reso = reso == Just (0,0) || reso == Just (0,1)


update : Msg -> Model -> Model
update msg model =
  case msg of
    MOp o    -> { model | op = o }
    Reso s   -> { model | op = if onlyEq (resoParse False s) && model.op /= Eq && model.op /= Ne then Eq else model.op, value = s, reso = resoParse False s }
    Aspect b -> { model | aspect = b }


init : Data -> (Data, Model)
init dat = (dat,
  { op     = Ge
  , reso   = Nothing
  , value  = ""
  , aspect = False
  })


toQuery : Model -> Maybe Query
toQuery model = Maybe.map (\(x,y) -> QTuple (if model.aspect then 9 else 8) model.op x y) model.reso

fromQuery : Data -> Query -> Maybe (Data, Model)
fromQuery dat q =
  case q of
    QTuple 8 op x y -> Just (dat, { op = op, reso = Just (x,y), value = resoFmt False x y, aspect = False })
    QTuple 9 op x y -> Just (dat, { op = op, reso = Just (x,y), value = resoFmt False x y, aspect = True  })
    _ -> Nothing


view : Model -> (Html Msg, () -> List (Html Msg))
view model =
  ( case model.reso of
      Nothing -> b [ class "grayedout" ] [ text "Resolution" ]
      Just (x,y) -> span [ class "nowrap" ] [ text <| (if x > 0 && model.aspect then "A " else "R ") ++ showOp model.op ++ " " ++ resoFmt False x y ]
  , \() ->
    [ div [ class "advheader", style "width" "250px" ]
      [ h3 [] [ text "Resolution" ]
      , div [ class "opts" ]
        [ div [ class "opselect" ] [ inputOp (onlyEq model.reso) model.op MOp ]
        , if model.op == Eq || model.op == Ne then text "" else
          linkRadio model.aspect Aspect [ span [ title "Match the aspect ratio of the given resolution" ] [ text "aspect" ] ]
        ]
      ]
    , inputText "" model.value Reso [style "width" "200px"] -- TODO: autocomplete
    ]
  )
