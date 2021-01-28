module AdvSearch.Engine exposing (..)

-- TODO: Add "unknown" option? (= empty string)

import Html exposing (..)
import Html.Attributes exposing (..)
import Set
import Lib.Autocomplete as A
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Gen.Api as GApi
import AdvSearch.Lib exposing (..)
import AdvSearch.Set as S



type alias Model =
  { sel    : S.Model String
  , conf   : A.Config Msg GApi.ApiEngines
  , search : A.Model GApi.ApiEngines
  }

type Msg
  = Sel (S.Msg String)
  | Search (A.Msg GApi.ApiEngines)


init : Data -> (Data, Model)
init dat =
  let (ndat, sel) = S.init dat
  in  ( { ndat | objid = ndat.objid + 1 }
      , { sel    = { sel | single = False }
        , conf   = { wrap = Search, id = "advsearch_eng" ++ String.fromInt ndat.objid, source = A.engineSource }
        , search = A.init ""
        }
      )


update : Data -> Msg -> Model -> (Data, Model, Cmd Msg)
update dat msg model =
  case msg of
    Sel m -> (dat, { model | sel = S.update m model.sel }, Cmd.none)
    Search m ->
      let (nm, c, res) = A.update model.conf m model.search
      in case res of
          Nothing -> (dat, { model | search = nm }, c)
          Just e -> (dat, { model | search = A.clear nm "", sel = S.update (S.Sel e.engine True) model.sel }, c)


toQuery m = S.toQuery (QStr 15) m.sel

fromQuery dat q =
  let f q2 = case q2 of
            QStr 15 op v -> Just (op, v)
            _ -> Nothing
  in S.fromQuery f dat q |> Maybe.map (\(ndat,sel) ->
      ( { ndat | objid = ndat.objid+1 }
      , { sel    = { sel | single = False }
        , conf   = { wrap = Search, id = "advsearch_eng" ++ String.fromInt ndat.objid, source = A.engineSource }
        , search = A.init ""
        }
      ))

view : Model -> (Html Msg, () -> List (Html Msg))
view model =
  ( case Set.toList model.sel.sel of
      []  -> b [ class "grayedout" ] [ text "Engine" ]
      [s] -> span [ class "nowrap" ] [  S.lblPrefix model.sel, text s ]
      l   -> span [] [ S.lblPrefix model.sel, text <| "Engines (" ++ String.fromInt (List.length l) ++ ")" ]
  , \() ->
    [ div [ class "advheader" ]
      [ h3 [] [ text "Engine" ]
      , Html.map Sel (S.opts model.sel False False)
      ]
    , ul [] <| List.map (\s ->
        li [] [ inputButton "X" (Sel (S.Sel s False)) [], text " ", text s ]
      ) (Set.toList model.sel.sel)
    , A.view model.conf model.search [ placeholder "Search..." ]
    ]
  )
