module AdvSearch.Anime exposing (..)

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
  , conf   : A.Config Msg GApi.ApiAnimeResult
  , search : A.Model GApi.ApiAnimeResult
  }

type Msg
  = Sel (S.Msg Int)
  | Search (A.Msg GApi.ApiAnimeResult)


init : Data -> (Data, Model)
init dat =
  let (ndat, sel) = S.init dat
  in  ( { ndat | objid = ndat.objid + 1 }
      , { sel    = { sel | single = False }
        , conf   = { wrap = Search, id = "advsearch_anime" ++ String.fromInt ndat.objid, source = A.animeSource }
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
            if Set.member s.id model.sel.sel then (dat, { model | search = nm }, c)
            else ( { dat | anime = Dict.insert s.id s dat.anime }
                 , { model | search = A.clear nm "", sel = S.update (S.Sel s.id True) model.sel }
                 , c )


toQuery m = S.toQuery (QInt 13) m.sel

fromQuery dat qf = S.fromQuery (\q ->
  case q of
    QInt 13 op v -> Just (op, v)
    _ -> Nothing) dat qf
  |> Maybe.map (\(ndat,sel) ->
    ( { ndat | objid = ndat.objid+1 }
    , { sel    = { sel | single = False }
      , conf   = { wrap = Search, id = "advsearch_anime" ++ String.fromInt ndat.objid, source = A.animeSource }
      , search = A.init ""
      }
    ))



view : Data -> Model -> (Html Msg, () -> List (Html Msg))
view dat model =
  ( case Set.toList model.sel.sel of
      []  -> b [ class "grayedout" ] [ text "Anime" ]
      [s] -> span [ class "nowrap" ]
             [ S.lblPrefix model.sel
             , b [ class "grayedout" ] [ text <| "a" ++ String.fromInt s ++ ":" ]
             , Dict.get s dat.anime |> Maybe.map (\e -> e.title) |> Maybe.withDefault "" |> text
             ]
      l   -> span [] [ S.lblPrefix model.sel, text <| "Anime (" ++ String.fromInt (List.length l) ++ ")" ]
  , \() ->
    [ div [ class "advheader" ]
      [ h3 [] [ text "Anime" ]
      , Html.map Sel (S.opts model.sel True True)
      ]
    , ul [] <| List.map (\s ->
        li [ style "overflow" "hidden", style "text-overflow" "ellipsis" ]
        [ inputButton "X" (Sel (S.Sel s False)) []
        , b [ class "grayedout" ] [ text <| " a" ++ String.fromInt s ++ ": " ]
        , Dict.get s dat.anime |> Maybe.map (\e -> e.title) |> Maybe.withDefault "" |> text
        ]
      ) (Set.toList model.sel.sel)
    , A.view model.conf model.search [ placeholder "Search..." ]
    ]
  )
