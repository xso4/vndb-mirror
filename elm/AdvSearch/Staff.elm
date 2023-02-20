module AdvSearch.Staff exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Set
import Dict
import Lib.Autocomplete as A
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Gen.Api as GApi
import AdvSearch.Lib exposing (..)
import AdvSearch.Set as S



type alias Model =
  { sel    : S.Model Int
  , conf   : A.Config Msg GApi.ApiStaffResult
  , search : A.Model GApi.ApiStaffResult
  }

type Msg
  = Sel (S.Msg Int)
  | Search (A.Msg GApi.ApiStaffResult)


init : Data -> (Data, Model)
init dat =
  let (ndat, sel) = S.init dat
  in  ( { ndat | objid = ndat.objid + 1 }
      , { sel    = { sel | single = False }
        , conf   = { wrap = Search, id = "xsearch_staff" ++ String.fromInt ndat.objid, source = A.staffSource }
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
          Just s ->
            if Set.member (vndbidNum s.id) model.sel.sel then (dat, { model | search = nm }, c)
            else ( { dat | staff = Dict.insert s.id s dat.staff }
                 , { model | search = A.clear nm "", sel = S.update (S.Sel (vndbidNum s.id) True) model.sel }
                 , c )


toQuery m = S.toQuery (QInt 3) m.sel

fromQuery dat qf = S.fromQuery (\q ->
  case q of
    QInt 3 op v -> Just (op, v)
    _ -> Nothing) dat qf
  |> Maybe.map (\(ndat,sel) ->
    ( { ndat | objid = ndat.objid+1 }
    , { sel    = { sel | single = False }
      , conf   = { wrap = Search, id = "xsearch_staff" ++ String.fromInt ndat.objid, source = A.staffSource }
      , search = A.init ""
      }
    ))



view : Data -> Model -> (Html Msg, () -> List (Html Msg))
view dat model =
  ( case Set.toList model.sel.sel of
      []  -> b [ class "grayedout" ] [ text "Name" ]
      [s] -> span [ class "nowrap" ]
             [ S.lblPrefix model.sel
             , b [ class "grayedout" ] [ text <| "s" ++ String.fromInt s ++ ":" ]
             , Dict.get (vndbid 's' s) dat.staff |> Maybe.map (\e -> e.title) |> Maybe.withDefault "" |> text
             ]
      l   -> span [] [ S.lblPrefix model.sel, text <| "Names (" ++ String.fromInt (List.length l) ++ ")" ]
  , \() ->
    [ div [ class "advheader" ]
      [ h3 [] [ text "Staff identifier" ]
      , Html.map Sel (S.opts model.sel False True)
      ]
    , ul [] <| List.map (\s ->
        li [ style "overflow" "hidden", style "text-overflow" "ellipsis" ]
        [ inputButton "X" (Sel (S.Sel s False)) []
        , b [ class "grayedout" ] [ text <| " s" ++ String.fromInt s ++ ": " ]
        , Dict.get (vndbid 's' s) dat.staff |> Maybe.map (\e -> a [ href ("/" ++ e.id), target "_blank", style "display" "inline" ] [ text e.title ]) |> Maybe.withDefault (text "")
        ]
      ) (Set.toList model.sel.sel)
    , A.view model.conf model.search [ placeholder "Search..." ]
    , b [ class "grayedout" ] [ text "All aliases of the selected staff entries are searched, not just the names you specified." ]
    ]
  )
