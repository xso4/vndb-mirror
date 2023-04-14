module AdvSearch.Resolution exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Lib.Autocomplete as A
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Gen.Api as GApi
import AdvSearch.Lib exposing (..)


type alias Model =
  { op     : Op
  , reso   : Maybe (Int,Int)
  , conf   : A.Config Msg GApi.ApiResolutions
  , search : A.Model GApi.ApiResolutions
  , aspect : Bool
  }


type Msg
  = MOp Op
  | Search (A.Msg GApi.ApiResolutions)
  | Aspect Bool


onlyEq : Maybe (Int,Int) -> Bool
onlyEq reso = reso == Just (0,0) || reso == Just (0,1)


update : Data -> Msg -> Model -> (Data, Model, Cmd Msg)
update dat msg model =
  case msg of
    MOp o    -> (dat, { model | op = o, aspect = o /= Eq && o /= Ne && model.aspect }, Cmd.none)
    Aspect b -> (dat, { model | aspect = b }, Cmd.none)
    Search m ->
      let (nm, c, en) = A.update model.conf m model.search
          search = Maybe.withDefault nm <| Maybe.map (\e -> A.clear nm e.resolution) en
          reso = resoParse True search.value
          op = if onlyEq reso && model.op /= Eq && model.op /= Ne then Eq else model.op
      in (dat, { model | search = search, reso = reso, op = op, aspect = op /= Eq && op /= Ne && model.aspect }, c)


init : Data -> (Data, Model)
init dat =
  ( { dat | objid = dat.objid+1 }
  , { op     = Ge
    , reso   = Nothing
    , conf   = { wrap = Search, id = "xsearch_reso" ++ String.fromInt dat.objid, source = A.resolutionSource }
    , search = A.init ""
    , aspect = False
    }
  )


toQuery : Model -> Maybe Query
toQuery model = Maybe.map (\(x,y) -> QTuple (if model.aspect then 9 else 8) model.op x y) model.reso

fromQuery : Data -> Query -> Maybe (Data, Model)
fromQuery dat q =
  let m op x y aspect = Just <| Tuple.mapSecond (\mod -> { mod | op = op, reso = Just (x,y), search = A.init (resoFmt False x y), aspect = aspect }) <| init dat
  in
  case q of
    QTuple 8 op x y -> m op x y False
    QTuple 9 op x y -> m op x y True
    _ -> Nothing


view : Model -> (Html Msg, () -> List (Html Msg))
view model =
  ( case model.reso of
      Nothing -> small [] [ text "Resolution" ]
      Just (x,y) -> span [ class "nowrap" ] [ text <| (if x > 0 && model.aspect then "A " else "R ") ++ showOp model.op ++ " " ++ resoFmt False x y ]
  , \() ->
    [ div [ class "advheader" ]
      [ h3 [] [ text "Resolution" ]
      , div [ class "opts" ]
        [ div [ class "opselect" ] [ inputOp (onlyEq model.reso) model.op MOp ]
        , if model.op == Eq || model.op == Ne then text "" else
          linkRadio model.aspect Aspect [ span [ title "Aspect ratio must be the same" ] [ text "aspect" ] ]
        ]
      ]
    , A.view model.conf model.search [ placeholder "width x height" ]
    ]
  )
