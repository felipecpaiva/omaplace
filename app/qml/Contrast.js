.pragma library
// Copied from omadials (logic/Contrast.js, MIT, same author): WCAG contrast helpers for the theme colours.
const CHANNEL_MAX=255, SRGB_BREAK=0.04045, SRGB_DIVISOR=12.92;
const SRGB_OFFSET=0.055, SRGB_SCALE=1.055, SRGB_EXPONENT=2.4;
const RED=0.2126, GREEN=0.7152, BLUE=0.0722, OFFSET=0.05;
const TEXT_RATIO=4.5, CONTROL_RATIO=3, LIGHT_LUMINANCE=0.5;
function rgb(hex) {
    if(!/^#[0-9a-f]{6}$/i.test(hex))throw new Error('Expected an RGB hex colour');
    return [parseInt(hex.slice(1,3),16),parseInt(hex.slice(3,5),16),parseInt(hex.slice(5,7),16)];
}
function linear(v) {const c=v/CHANNEL_MAX;return c<=SRGB_BREAK ? c/SRGB_DIVISOR : Math.pow((c+SRGB_OFFSET)/SRGB_SCALE,SRGB_EXPONENT);}
function luminance(hex) {const c=rgb(hex).map(linear);return c[0]*RED+c[1]*GREEN+c[2]*BLUE;}
function ratio(a,b) {const x=luminance(a),y=luminance(b);return (Math.max(x,y)+OFFSET)/(Math.min(x,y)+OFFSET);}
function isLight(background) {return luminance(background)>LIGHT_LUMINANCE;}
function accent(palette) {return ratio(palette.accent,palette.background)>=CONTROL_RATIO ? palette.accent : palette.foreground;}
function roles(palette) {
    const fill=accent(palette);
    return {fill:fill,ink:palette.background,text:palette.foreground,light:isLight(palette.background),
        textPass:ratio(palette.foreground,palette.background)>=TEXT_RATIO,controlsPass:ratio(fill,palette.background)>=CONTROL_RATIO};
}
// Snap a failing interpolated pair to the already contrast-resolved endpoint.
function transitionPair(current,target,text) {return ratio(current.ink,current.fill)>=(text ? TEXT_RATIO : CONTROL_RATIO) ? current : target;}
