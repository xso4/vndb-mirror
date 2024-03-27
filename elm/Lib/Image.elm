module Lib.Image exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Process
import Task
import File exposing (File)
import Lib.Html exposing (..)
import Lib.Api as Api
import Lib.Util exposing (imageUrl)
import Gen.Api as GApi
import Gen.Image as GI
import Gen.ImageVote as GIV


type State
  = Normal
  | Invalid
  | NotFound
  | Loading
  | Error GApi.Response

type alias Image =
  { id        : Maybe String
  , img       : Maybe GApi.ApiImageResult
  , imgState  : State
  , saveState : Api.State
  , saveTimer : Bool
  }


info : Maybe GApi.ApiImageResult -> Image
info img =
  { id        = Maybe.map (\i -> i.id) img
  , img       = img
  , imgState  = Normal
  , saveState = Api.Normal
  , saveTimer = False
  }


-- Fetch image info from the ID
new : Bool -> String -> (Image, Cmd Msg)
new valid id =
  ( { id        = if id == "" then Nothing else Just id
    , img       = Nothing
    , imgState  = if id == "" then Normal else if valid then Loading else Invalid
    , saveState = Api.Normal
    , saveTimer = False
    }
  , if valid && id /= "" then GI.send { id = id } Loaded else Cmd.none
  )


-- Upload a new image from a form
upload : Api.ImageType -> File -> (Image, Cmd Msg)
upload t f =
  ( { id        = Nothing
    , img       = Nothing
    , imgState  = Loading
    , saveState = Api.Normal
    , saveTimer = False
    }
  , Api.postImage t f Loaded)


type Msg
  = Loaded GApi.Response
  | MySex Int Bool
  | MyVio Int Bool
  | Save
  | Saved GApi.Response


update : Msg -> Image -> (Image, Cmd Msg)
update msg model =
  let
    save m =
      if m.saveTimer || Maybe.withDefault True (Maybe.map (\i -> i.token == Nothing || i.my_sexual == Nothing || i.my_violence == Nothing) m.img)
      then (m, Cmd.none)
      else ({ m | saveTimer = True }, Task.perform (always Save) (Process.sleep 1000))
  in
  case msg of
    Loaded (GApi.ImageResult [i]) -> ({ model | id = Just i.id, img = Just i, imgState = Normal}, Cmd.none)
    Loaded (GApi.ImageResult []) -> ({ model | imgState = NotFound}, Cmd.none)
    Loaded e -> ({ model | imgState = Error e }, Cmd.none)

    MySex v _ -> save { model | img = Maybe.map (\i -> { i | my_sexual   = Just v }) model.img }
    MyVio v _ -> save { model | img = Maybe.map (\i -> { i | my_violence = Just v }) model.img }

    Save ->
      case Maybe.map (\i -> (i.token, i.my_sexual, i.my_violence)) model.img of
        Just (Just token, Just sex, Just vio) ->
          ( { model | saveTimer = False, saveState = Api.Loading }
          , GIV.send { votes = [{ id = Maybe.withDefault "" model.id, token = token, sexual = sex, violence = vio, overrule = False }] } Saved)
        _ -> (model, Cmd.none)
    Saved (GApi.Success) -> ({ model | saveState = Api.Normal}, Cmd.none)
    Saved e -> ({ model | saveState = Api.Error e }, Cmd.none)



isValid : Image -> Bool
isValid img = img.imgState == Normal


viewImg : Image -> Html m
viewImg image =
  case (image.imgState, image.img) of
    (Loading, _) -> div [ class "spinner" ] []
    (NotFound, _) ->b [] [ text "Image not found." ]
    (Invalid, _) -> b [] [ text "Invalid image ID." ]
    (Error e, _) -> b [] [ text <| Api.showResponse e ]
    (_, Nothing) -> text "No image."
    (_, Just i) ->
      let
        maxWidth  = toFloat <| if String.startsWith "sf" i.id then 136 else 10000
        maxHeight = toFloat <| if String.startsWith "sf" i.id then 102 else 10000
        sWidth    = maxWidth  / toFloat i.width
        sHeight   = maxHeight / toFloat i.height
        scale     = Basics.min 1 <| if sWidth < sHeight then sWidth else sHeight
        imgWidth  = round <| scale * toFloat i.width
        imgHeight = round <| scale * toFloat i.height
      in
      -- TODO: Onclick iv.js support for screenshot thumbnails
      label [ class "imghover", style "width" (String.fromInt imgWidth++"px"), style "height" (String.fromInt imgHeight++"px") ]
      [ div [ class "imghover--visible" ]
        [ if String.startsWith "sf" i.id
          then a [ href (imageUrl "" i.id), attribute "data-iv" <| String.fromInt i.width ++ "x" ++ String.fromInt i.height ++ ":scr" ]
               [ img [ src <| imageUrl ".t" i.id ] [] ]
          else img [ src <| imageUrl "" i.id ] []
        , a [ class "imghover--overlay", href <| "/img/"++i.id ] <|
          case (i.sexual_avg, i.violence_avg) of
            (Just sex, Just vio) ->
              -- XXX: These thresholds are subject to change, maybe just show the numbers here?
              [ text <| if sex > 1.3 then "Explicit" else if sex > 0.4 then "Suggestive" else "Safe"
              , text " / "
              , text <| if vio > 1.3 then "Brutal"   else if vio > 0.4 then "Violent"    else "Tame"
              , text <| " (" ++ String.fromInt i.votecount ++ ")"
              ]
            _ -> [ text "Not flagged" ]
        ]
      ]


viewVote : Image -> (Msg -> a) -> a -> Maybe (Html a)
viewVote model wrap msg =
  let
    rad i sex val = input
      [ type_ "radio"
      , tabindex 10
      , required True
      , onInvalid msg
      , onCheck <| \b -> wrap <| (if sex then MySex else MyVio) val b
      , checked <| (if sex then i.my_sexual else i.my_violence) == Just val
      , name <| "imgvote-" ++ (if sex then "sex" else "vio") ++ "-" ++ Maybe.withDefault "" model.id
      ] []
    vote i = table []
      [ thead [] [ tr []
        [ td [] [ text "Sexual ", if model.saveState == Api.Loading then span [ class "spinner" ] [] else text "" ]
        , td [] [ text "Violence" ]
        ] ]
      , tfoot [] <|
        case model.saveState of
          Api.Error e -> [ tr [] [ td [ colspan 2 ] [ b [] [ text (Api.showResponse e) ] ] ] ]
          _ -> []
      , tr []
        [ td [ style "white-space" "nowrap" ]
          [ label [] [ rad i True 0, text " Safe" ], br [] []
          , label [] [ rad i True 1, text " Suggestive" ], br [] []
          , label [] [ rad i True 2, text " Explicit" ]
          ]
        , td [ style "white-space" "nowrap" ]
          [ label [] [ rad i False 0, text " Tame" ], br [] []
          , label [] [ rad i False 1, text " Violent" ], br [] []
          , label [] [ rad i False 2, text " Brutal" ]
          ]
        ]
      ]
  in case model.img of
      Nothing -> Nothing
      Just i ->
        if i.token == Nothing then Nothing
        else Just (vote i)
