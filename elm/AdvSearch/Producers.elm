module AdvSearch.Producers exposing (..)

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
  , conf   : A.Config Msg GApi.ApiProducerResult
  , search : A.Model GApi.ApiProducerResult
  }

type Msg
  = Sel (S.Msg Int)
  | Search (A.Msg GApi.ApiProducerResult)


init : Data -> (Data, Model)
init dat =
  let (ndat, sel) = S.init dat
  in  ( { ndat | objid = ndat.objid + 1 }
      , { sel    = { sel | single = False }
        , conf   = { wrap = Search, id = "advsearch_prod" ++ String.fromInt ndat.objid, source = A.producerSource }
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
          Just p ->
            if Set.member (vndbidNum p.id) model.sel.sel then (dat, { model | search = nm }, c)
            else ( { dat | producers = Dict.insert p.id p dat.producers }
                 , { model | search = A.clear nm "", sel = S.update (S.Sel (vndbidNum p.id) True) model.sel }
                 , c )


toQuery n m = S.toQuery (QInt n) m.sel

fromQuery n dat qf = S.fromQuery (\q ->
  case q of
    QInt id op v -> if id == n then Just (op, v) else Nothing
    _ -> Nothing) dat qf
  |> Maybe.map (\(ndat,sel) ->
    ( { ndat | objid = ndat.objid+1 }
    , { sel    = { sel | single = False }
      , conf   = { wrap = Search, id = "advsearch_prod" ++ String.fromInt ndat.objid, source = A.producerSource }
      , search = A.init ""
      }
    ))



view : String -> Data -> Model -> (Html Msg, () -> List (Html Msg))
view lbl dat model =
  ( case Set.toList model.sel.sel of
      []  -> b [ class "grayedout" ] [ text lbl ]
      [s] -> span [ class "nowrap" ]
             [ S.lblPrefix model.sel
             , b [ class "grayedout" ] [ text <| "p" ++ String.fromInt s ++ ":" ]
             , Dict.get (vndbid 'p' s) dat.producers |> Maybe.map (\p -> p.name) |> Maybe.withDefault "" |> text
             ]
      l   -> span [] [ S.lblPrefix model.sel, text <| lbl ++ "s (" ++ String.fromInt (List.length l) ++ ")" ]
  , \() ->
    [ div [ class "advheader" ]
      [ h3 [] [ text "Producer identifier" ]
      , Html.map Sel (S.opts model.sel False True)
      ]
    , ul [] <| List.map (\s ->
        li [ style "overflow" "hidden", style "text-overflow" "ellipsis" ]
        [ inputButton "X" (Sel (S.Sel s False)) []
        , b [ class "grayedout" ] [ text <| " p" ++ String.fromInt s ++ ": " ]
        , Dict.get (vndbid 'p' s) dat.producers |> Maybe.map (\p -> a [ href ("/" ++ p.id), target "_blank", style "display" "inline" ] [ text p.name ]) |> Maybe.withDefault (text "")
        ]
      ) (Set.toList model.sel.sel)
    , A.view model.conf model.search [ placeholder "Search..." ]
    ]
  )
