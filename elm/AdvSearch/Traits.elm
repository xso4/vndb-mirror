module AdvSearch.Traits exposing (..)

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
  { sel     : S.Model Int
  , conf    : A.Config Msg GApi.ApiTraitResult
  , search  : A.Model GApi.ApiTraitResult
  , spoiler : Int
  }

type Msg
  = Sel (S.Msg Int)
  | Spoiler
  | Search (A.Msg GApi.ApiTraitResult)


init : Data -> (Data, Model)
init dat =
  let (ndat, sel) = S.init dat
  in  ( { ndat | objid = ndat.objid + 1 }
      , { sel     = { sel | single = False, and = True }
        , conf    = { wrap = Search, id = "advsearch_trait" ++ String.fromInt ndat.objid, source = A.traitSource }
        , search  = A.init ""
        , spoiler = dat.defaultSpoil
        }
      )


update : Data -> Msg -> Model -> (Data, Model, Cmd Msg)
update dat msg model =
  case msg of
    Sel m -> (dat, { model | sel = S.update m model.sel }, Cmd.none)
    Spoiler -> (dat, { model | spoiler = if model.spoiler < 2 then model.spoiler + 1 else 0 }, Cmd.none)
    Search m ->
      let (nm, c, res) = A.update model.conf m model.search
      in case res of
          Nothing -> (dat, { model | search = nm }, c)
          Just t ->
            ( { dat | traits = Dict.insert t.id t dat.traits }
            , { model | search = A.clear nm "", sel = S.update (S.Sel t.id True) model.sel }
            , c )


toQuery m = S.toQuery (\o t -> if m.spoiler == 0 then QInt 13 o t else QTuple 13 o t m.spoiler) m.sel

fromQuery spoil dat q =
  let f qr = case qr of
              QInt 13 op t -> if spoil == 0 then Just (op, t) else Nothing
              QTuple 13 op t v -> if v == spoil then Just (op, t) else Nothing
              _ -> Nothing
  in
  S.fromQuery f dat q |> Maybe.map (\(ndat,sel) ->
    ( { ndat | objid = ndat.objid+1 }
    , { sel     = { sel | single = False, and = sel.and || Set.size sel.sel == 1 }
      , conf    = { wrap = Search, id = "advsearch_trait" ++ String.fromInt ndat.objid, source = A.traitSource }
      , search  = A.init ""
      , spoiler = spoil
      }
    ))


view : Data -> Model -> (Html Msg, () -> List (Html Msg))
view dat model =
  ( case Set.toList model.sel.sel of
      []  -> b [ class "grayedout" ] [ text "Traits" ]
      [s] -> span [ class "nowrap" ]
             [ S.lblPrefix model.sel
             , b [ class "grayedout" ] [ text <| "i" ++ String.fromInt s ++ ":" ]
             , Dict.get s dat.traits |> Maybe.map (\t -> t.name) |> Maybe.withDefault "" |> text
             ]
      l   -> span [] [ S.lblPrefix model.sel, text <| "Traits (" ++ String.fromInt (List.length l) ++ ")" ]
  , \() ->
    [ div [ class "advheader" ]
      [ h3 [] [ text "Traits" ]
      , div [ class "opts" ]
        [ Html.map Sel (S.optsMode model.sel True False)
        , a [ href "#", onClickD Spoiler ]
          [ text <| if model.spoiler == 0 then "no spoilers" else if model.spoiler == 1 then "minor spoilers" else "major spoilers" ]
        , linkRadio model.sel.neg (Sel << S.Neg) [ text "invert" ]
        ]
      ]
    , ul [] <| List.map (\t ->
        li []
        [ inputButton "X" (Sel (S.Sel t False)) []
        , b [ class "grayedout" ] [ text <| " g" ++ String.fromInt t ++ ": " ]
        , Dict.get t dat.traits |> Maybe.map (\e -> span []
          [ Maybe.withDefault (text "") <| Maybe.map (\g -> b [ class "grayedout" ] [ text (g ++ " / ") ]) e.group_name
          , text e.name ]) |> Maybe.withDefault (text "")
        ]
      ) (Set.toList model.sel.sel)
    , A.view model.conf model.search [ placeholder "Search..." ]
    ]
  )
