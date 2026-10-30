// Append to a generated progression page after its main script; run in Chromium.
(async function () {
 const assert=(ok,message)=>{if(!ok)throw Error(message)};
 const routeGraph=zsvg.outerHTML,routeMap=zcv.toDataURL();
 const clickNode=id=>{const node=svg.querySelector(`.unlock-stop[data-node="${id}"]`);assert(node,'Missing station '+id);node.dispatchEvent(new MouseEvent('click'))};
 const index=id=>D.nodes.findIndex(n=>n.id===id);
 for(const unplaced of [false,true])for(const unavailable of [false,true]){
  document.getElementById('hide-unplaced').checked=unplaced;
  document.getElementById('hide-unavailable').checked=unavailable;drawTop();
  assert(svg.textContent.includes('Ape beaten')&&svg.textContent.includes('Guardian beaten'),'Boss filtered out');
  for(const stop of [...svg.querySelectorAll('.unlock-stop')])stop.dispatchEvent(new MouseEvent('click'));
  for(const edge of [...svg.querySelectorAll('.unlock-segment')])edge.dispatchEvent(new MouseEvent('click'));
  assert(!document.getElementById('unlock-path').textContent.includes('undefined'),'Undefined action');
 }
 document.getElementById('hide-unplaced').checked=false;document.getElementById('hide-unavailable').checked=false;drawTop();
 const end=index('attack+dash'),dash=index('dash');assert(end>=0&&dash>=0,'Missing fixture states');
 clickNode(end);const before=cv.toDataURL(),summary=document.getElementById('map-selection').textContent;
 clickNode(dash);
 assert(cv.toDataURL()===before&&document.getElementById('map-selection').textContent===summary,'First back click moved map');
 assert(unlockPendingStep===dash&&unlockSelectedPath[1]===dash,'First back click did not reroute');
 clickNode(dash);assert(unlockMapState===dash&&unlockPendingStep===null,'Second back click did not select map');
 clickNode(end);assert(unlockSelectedPath[1]===dash&&unlockMapState===end,'Forward click lost earlier route');
 assert(routeGraph===zsvg.outerHTML&&routeMap===zcv.toDataURL(),'Graph 2 was modified');
 const selectedMap=cv.toDataURL(),selectedRoute=unlockSelectedPath.join(',');
 document.getElementById('tab-routes').click();
 assert(document.getElementById('unlock-map').hidden&&!document.getElementById('route-map').hidden,'Routes tab visibility');
 document.getElementById('tab-unlocks').click();
 assert(!document.getElementById('unlock-map').hidden&&document.getElementById('route-map').hidden,'Progression tab visibility');
 assert(cv.toDataURL()===selectedMap&&unlockSelectedPath.join(',')===selectedRoute,'Tab switch reset selection');
 const mapBox=document.getElementById('unlock-map').getBoundingClientRect(),graphBox=document.getElementById('unlock-graph').getBoundingClientRect();
 assert(mapBox.width>0&&graphBox.width>0,'Hidden active pane');
 if(window.innerWidth>850)assert(mapBox.width>graphBox.width*1.5,'Map is not the dominant pane');
 const first=svg.querySelector('.unlock-stop');first.dispatchEvent(new MouseEvent('mouseenter'));
 assert(!tip.textContent.includes('undefined'),'Invalid hover text');first.dispatchEvent(new MouseEvent('mouseleave'));
 await new Promise(resolve=>setTimeout(resolve,150));
 assert(!document.body.dataset.reviewXss,'Room title executed');
 assert(!window.reviewErrors?.length,(window.reviewErrors||[]).join(';'));
 document.body.dataset.reviewResult='passed';
})();
