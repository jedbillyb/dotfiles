// GPU video decode (Renoir VA-API) - cuts CPU heat while watching video
user_pref("media.hardware-video-decoding.enabled", true);
user_pref("media.ffmpeg.vaapi.enabled", true);
// Renoir has no AV1 decode; disabling AV1 makes YouTube serve VP9 which the GPU decodes
user_pref("media.av1.enabled", false);

// Load chrome/userContent.css (hides the focus ring on fullscreen video).
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Fullscreen (F on a video) fills the Firefox window instead of the whole
// screen, so waybar stays visible and the video sits below it.
user_pref("full-screen-api.ignore-widgets", true);
