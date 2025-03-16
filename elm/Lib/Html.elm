module Lib.Html exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as JD
import List
import Lib.Api as Api
import Lib.Util exposing (..)
import Gen.Types as T


-- onClick with stopPropagation & preventDefault
onClickN : m -> Attribute m
onClickN action = custom "click" (JD.succeed { message = action, stopPropagation = True, preventDefault = True})

-- onClick with preventDefault
onClickD : m -> Attribute m
onClickD action = custom "click" (JD.succeed { message = action, stopPropagation = False, preventDefault = True})


-- Quick short-hand way of creating a form that can be disabled.
-- Usage:
--   form_ id Submit_msg (state == Disabled) [contents]
form_ : String -> msg -> Bool -> List (Html msg) -> Html msg
form_ s sub dis cont = Html.form [ id s, onSubmit sub ]
  [ fieldset [disabled dis] cont ]


inputButton : String -> m -> List (Attribute m) -> Html m
inputButton val onch attrs =
  input ([ type_ "button", class "submit", tabindex 10, value val, onClick onch] ++ attrs) []


-- Submit button with loading indicator and error message display
submitButton : String -> Api.State -> Bool -> Html m
submitButton val state valid = span []
   [ input [ type_ "submit", class "submit", tabindex 10, value val, disabled (state == Api.Loading || not valid) ] []
   , case state of
       Api.Error r -> p [] [ b [] [ text <| Api.showResponse r ] ]
       _ -> if valid
            then text ""
            else p [] [ b [] [ text "The form contains errors, please fix these before submitting. " ] ]
   , if state == Api.Loading
     then div [ class "spinner" ] []
     else text ""
   ]


inputSelect : String -> a -> (a -> m) -> List (Attribute m) -> List (a, String) -> Html m
inputSelect nam sel onch attrs lst =
  let
    opt n (id, name) = option [ value (String.fromInt n), selected (id == sel) ] [ text name ]
    call first n =
      case List.drop (Maybe.withDefault 0 <| String.toInt n) lst |> List.head of
        Just (id, name) -> onch id
        Nothing -> onch first
    ev =
      case List.head lst of
        Just first -> [ onInput <| call <| Tuple.first first ]
        Nothing -> []
  in select (
        [ tabindex 10 ]
        ++ ev
        ++ attrs
        ++ (if nam == "" then [] else [ id nam, name nam ])
      ) <| List.indexedMap opt lst


inputText : String -> String -> (String -> m) -> List (Attribute m) -> Html m
inputText nam val onch attrs = input (
    [ type_ "text"
    , class "text"
    , tabindex 10
    , value val
    , onInput onch
    ]
    ++ attrs
    ++ (if nam == "" then [] else [ id nam, name nam ])
  ) []


inputCheck : String -> Bool -> (Bool -> m) -> Html m
inputCheck nam val onch = input (
    [ type_ "checkbox"
    , tabindex 10
    , onCheck onch
    , checked val
    ]
    ++ (if nam == "" then [] else [ id nam, name nam ])
  ) []


-- Similar to inputCheck and inputRadio with a label, except this is just a link.
linkRadio : Bool -> (Bool -> m) -> List (Html m) -> Html m
linkRadio val onch content =
  a [ href "#", onClickD (onch (not val)), class "linkradio", classList [("checked", val)] ] content


langIcon : String -> Html m
langIcon l = abbr [ class ("icon-lang-"++l), title (Maybe.withDefault "" <| lookup l T.languages) ] [ text " " ]

platformIcon : String -> Html m
platformIcon l = abbr [ class ("icon-plat-"++l), title (Maybe.withDefault "" <| lookup l T.platforms) ] [ text " " ]

releaseTypeIcon : String -> Html m
releaseTypeIcon t = abbr [ class ("icon-rt"++t), title (Maybe.withDefault "" <| lookup t T.releaseTypes) ] [ text " " ]
