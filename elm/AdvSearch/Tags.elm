module AdvSearch.Tags exposing (..)

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
  { sel     : S.Model (Int,Int) -- Tag, Level
  , conf    : A.Config Msg GApi.ApiTagResult
  , search  : A.Model GApi.ApiTagResult
  , spoiler : Int
  }

type Msg
  = Sel (S.Msg (Int,Int))
  | Level (Int,Int) Int
  | Spoiler
  | Search (A.Msg GApi.ApiTagResult)


init : Data -> (Data, Model)
init dat =
  let (ndat, sel) = S.init dat
  in  ( { ndat | objid = ndat.objid + 1 }
      , { sel     = { sel | single = False, and = True }
        , conf    = { wrap = Search, id = "advsearch_tag" ++ String.fromInt ndat.objid, source = A.tagSource }
        , search  = A.init ""
        , spoiler = dat.defaultSpoil
        }
      )


update : Data -> Msg -> Model -> (Data, Model, Cmd Msg)
update dat msg model =
  case msg of
    Sel m -> (dat, { model | sel = S.update m model.sel }, Cmd.none)
    Level (t,ol) nl -> (dat, { model | sel = S.update (S.Sel (t,ol) False) model.sel |> S.update (S.Sel (t,nl) True) }, Cmd.none)
    Spoiler -> (dat, { model | spoiler = if model.spoiler < 2 then model.spoiler + 1 else 0 }, Cmd.none)
    Search m ->
      let (nm, c, res) = A.update model.conf m model.search
      in case res of
          Nothing -> (dat, { model | search = nm }, c)
          Just t ->
            ( { dat | tags = Dict.insert t.id t dat.tags }
            , { model | search = A.clear nm "", sel = S.update (S.Sel (t.id,0) True) model.sel }
            , c )


toQuery m = S.toQuery (\o (t,l) -> if m.spoiler == 0 && l == 0 then QInt 8 o t else QTuple 8 o t (l*3+m.spoiler)) m.sel

fromQuery spoil dat q =
  let f qr = case qr of
              QInt 8 op t -> if spoil == 0 then Just (op, (t,0)) else Nothing
              QTuple 8 op t v -> if modBy 3 v == spoil then Just (op, (t,v//3)) else Nothing
              _ -> Nothing
  in
  S.fromQuery f dat q |> Maybe.map (\(ndat,sel) ->
    ( { ndat | objid = ndat.objid+1 }
    , { sel     = { sel | single = False }
      , conf    = { wrap = Search, id = "advsearch_tag" ++ String.fromInt ndat.objid, source = A.tagSource }
      , search  = A.init ""
      , spoiler = spoil
      }
    ))


view : Data -> Model -> (Html Msg, () -> List (Html Msg))
view dat model =
  ( case Set.toList model.sel.sel of
      []  -> b [ class "grayedout" ] [ text "Tags" ]
      [(s,_)] -> span [ class "nowrap" ]
             [ S.lblPrefix model.sel
             , b [ class "grayedout" ] [ text <| "g" ++ String.fromInt s ++ ":" ]
             , Dict.get s dat.tags |> Maybe.map (\t -> t.name) |> Maybe.withDefault "" |> text
             ]
      l   -> span [] [ S.lblPrefix model.sel, text <| "Tags (" ++ String.fromInt (List.length l) ++ ")" ]
  , \() ->
    [ div [ class "advheader" ]
      [ h3 [] [ text "Tags" ]
      , div [ class "opts" ]
        [ Html.map Sel (S.optsMode model.sel True False)
        , a [ href "#", onClickD Spoiler ]
          [ text <| if model.spoiler == 0 then "no spoilers" else if model.spoiler == 1 then "minor spoilers" else "major spoilers" ]
        , linkRadio model.sel.neg (Sel << S.Neg) [ text "invert" ]
        ]
      ]
    , ul [] <| List.map (\(t,l) ->
        li []
        [ inputButton "X" (Sel (S.Sel (t,l) False)) []
        , inputSelect "" l (Level (t,l)) [style "width" "60px"] <|
          (0, "any")
          :: List.map (\i -> (i, String.fromInt (i//5) ++ "." ++ String.fromInt (2*(modBy 5 i)) ++ "+")) (List.range 1 14)
          ++ [(15, "3.0")]
        , b [ class "grayedout" ] [ text <| " g" ++ String.fromInt t ++ ": " ]
        , Dict.get t dat.tags |> Maybe.map (\e -> e.name) |> Maybe.withDefault "" |> text
        ]
      ) (Set.toList model.sel.sel)
    , A.view model.conf model.search [ placeholder "Search..." ]
    ]
  )
