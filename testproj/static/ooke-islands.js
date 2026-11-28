/*
 * ooke-islands.js - Hydration loader for ooke island architecture.
 * Strategies: load | visible | idle | none
 * Fetches WASM, falls back to JS module.  <800 bytes minified.
 */
(function(){
  var B='/static/islands/',D=document,W=window;

  function run(el){
    var n=el.getAttribute('data-island');
    if(!n)return;
    fetch(B+n+'.wasm').then(function(r){
      if(!r.ok)throw 0;return r.arrayBuffer();
    }).then(function(b){
      return WebAssembly.instantiate(b);
    }).then(function(w){
      var f=w.instance.exports.render;
      if(f)el.innerHTML=f();
    }).catch(function(){
      import(B+n+'.js').then(function(m){
        var f=m.default||m.render;
        if(f)el.innerHTML=f();
      }).catch(function(){});
    });
  }

  function init(){
    D.querySelectorAll('[data-island]').forEach(function(el){
      var s=(el.getAttribute('data-hydrate')||'load')[0];
      if(s==='n')return;
      if(s==='v'){
        if(!W.IntersectionObserver){run(el);return;}
        var o=new IntersectionObserver(function(e){
          if(e[0].isIntersecting){o.disconnect();run(el);}
        });
        o.observe(el);
      }else if(s==='i'){
        (W.requestIdleCallback||function(c){setTimeout(c,200)})(function(){run(el)});
      }else run(el);
    });
  }

  D.readyState==='loading'?D.addEventListener('DOMContentLoaded',init):init();
})();
