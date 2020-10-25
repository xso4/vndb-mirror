-- Attempt to abstract away a single widget for set-style selections.

module AdvSearch.Set exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Set
import Lib.DropDown as DD
import Lib.Api as Api
import Lib.Html exposing (..)
import Lib.Util exposing (..)
import Gen.Types as GT


type alias Model a =
  { sel    : Set.Set a
  , dd     : DD.Config (Msg a)
  , and    : Bool
  , neg    : Bool
  }

type Msg a
  = Toggle Bool
  | Sel a Bool
  | And Bool
  | Neg Bool


init : Bool -> String -> Model a
init id =
  { sel = Set.empty
  , dd  = DD.init id Toggle
  , and = False
  , neg = False
  }

update : Msg a -> Model a -> (Model a, Cmd (Msg a))
update msg model =
  case msg of
    Toggle b -> ({ model | dd = DD.toggle model.dd b }, Cmd.none)
    Sel s b  -> ({ model | sel = if b then Set.insert s model.sel else Set.remove s model.sel }, Cmd.none)
    And b    -> ({ model | and = b }, Cmd.none)
    Neg b    -> ({ model | neg = b }, Cmd.none)


view : Bool -> String -> List a -> (a -> List (Html (Msg a))) -> Model a -> Html (Msg a)
view canAnd ddLabel items itemView model = div [ class "elm_dd_input" ]
  [ DD.view model.dd Api.Normal
    (case Set.size model.sel of
      0 -> b [ class "grayedout" ] [ text ddLabel ]
      1 -> span [] (Set.toList model.sel |> List.head |> Maybe.map itemView |> Maybe.withDefault [])
      n -> text <| ddLabel ++ " (" ++ String.fromInt n ++ ")")
     <| \() -> -- TODO: Styling
       [ if not canAnd then text "" else div []
         [ linkRadio model.and And [ text "and" ]
         , text " / "
         , linkRadio (not model.and) (\b -> And (not b)) [ text "or" ]
         ]
       , div []
         [ linkRadio (not model.neg) (\b -> Neg (not b)) [ text "include" ]
         , text " / "
         , linkRadio model.neg Neg [ text "exclude" ]
         ]
       --, ul [ style "columns" "2"] <| List.map (\(l,t) -> li [] [ linkRadio (Set.member l model.langSel) (LangSel l) [ langIcon l, text t ] ]) GT.languages
       , ul [ style "columns" "2"] <| List.map (\l -> li [] [ linkRadio (Set.member l model.sel) (Sel l) (itemView l) ]) items
       ]
  ]
