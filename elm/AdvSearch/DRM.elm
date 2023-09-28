module AdvSearch.DRM exposing (..)

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
  , conf   : A.Config Msg GApi.ApiDRM
  , search : A.Model GApi.ApiDRM
  }

type Msg
  = Sel (S.Msg String)
  | Search (A.Msg GApi.ApiDRM)


init : Data -> (Data, Model)
init dat =
  let (ndat, sel) = S.init dat
  in  ( { ndat | objid = ndat.objid + 1 }
      , { sel    = { sel | single = False }
        , conf   = { wrap = Search, id = "xsearch_drm" ++ String.fromInt ndat.objid, source = A.drmSource }
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
          Just e -> (dat, { model | search = A.clear nm "", sel = S.update (S.Sel e.name True) model.sel }, c)


toQuery m = S.toQuery (QStr 20) m.sel

fromQuery dat q =
  let f q2 = case q2 of
            QStr 20 op v -> Just (op, v)
            _ -> Nothing
  in S.fromQuery f dat q |> Maybe.map (\(ndat,sel) ->
      ( { ndat | objid = ndat.objid+1 }
      , { sel    = { sel | single = False }
        , conf   = { wrap = Search, id = "xsearch_drm" ++ String.fromInt ndat.objid, source = A.drmSource }
        , search = A.init ""
        }
      ))

view : Model -> (Html Msg, () -> List (Html Msg))
view model =
  ( case Set.toList model.sel.sel of
      []  -> small [] [ text "DRM implementation" ]
      [s] -> span [ class "nowrap" ] [ S.lblPrefix model.sel, text s ]
      l   -> span [] [ S.lblPrefix model.sel, text <| "DRM (" ++ String.fromInt (List.length l) ++ ")" ]
  , \() ->
    [ div [ class "advheader" ]
      [ h3 [] [ text "DRM implementation" ]
      , Html.map Sel (S.opts model.sel False False)
      ]
    , ul [] <| List.map (\s ->
        li [] [ inputButton "X" (Sel (S.Sel s False)) [], text " ", text s ]
      ) <| List.filter (\x -> x /= "") <| Set.toList model.sel.sel
    , A.view model.conf model.search [ placeholder "Search..." ]
    ]
  )
