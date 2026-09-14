import { supabase } from "./supabase-client.js";

const params = new URLSearchParams(window.location.search);
const patternId = params.get("pattern_id");
const title = document.getElementById("guideTitle");
const status = document.getElementById("guideStatus");
const stage = document.getElementById("guideStage");
const image = document.getElementById("referenceImage");
const overlay = document.getElementById("guideOverlay");
const hybrid = document.getElementById("hybridOverlay");
const legend = document.getElementById("guideLegend");
const itemsList = document.getElementById("guideItems");

function uuidLike(v){return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v||"");}

function drawBox(item){
  overlay.replaceChildren();
  const [ymin,xmin,ymax,xmax]=item.box_2d.map(Number);
  const r=document.createElementNS("http://www.w3.org/2000/svg","rect");
  r.setAttribute("x",xmin);r.setAttribute("y",ymin);
  r.setAttribute("width",Math.max(0,xmax-xmin));r.setAttribute("height",Math.max(0,ymax-ymin));
  r.setAttribute("class","gemini-box");overlay.append(r);
}

function sobelPrimaryRoi(item){
  const maxSide=900;
  const scale=Math.min(1,maxSide/Math.max(image.naturalWidth,image.naturalHeight));
  const w=Math.max(320,Math.round(image.naturalWidth*scale));
  const h=Math.max(320,Math.round(image.naturalHeight*scale));
  hybrid.width=w;hybrid.height=h;

  const src=document.createElement("canvas");src.width=w;src.height=h;
  const ctx=src.getContext("2d",{willReadFrequently:true});
  ctx.drawImage(image,0,0,w,h);
  const rgba=ctx.getImageData(0,0,w,h).data;
  const gray=new Float32Array(w*h);
  for(let p=0,i=0;p<gray.length;p++,i+=4) gray[p]=rgba[i]*.299+rgba[i+1]*.587+rgba[i+2]*.114;

  const [y0n,x0n,y1n,x1n]=item.box_2d.map(Number);
  const pad=.006;
  const x0=Math.max(1,Math.floor((x0n/1000-pad)*w));
  const x1=Math.min(w-2,Math.ceil((x1n/1000+pad)*w));
  const y0=Math.max(1,Math.floor((y0n/1000-pad)*h));
  const y1=Math.min(h-2,Math.ceil((y1n/1000+pad)*h));

  const mags=[];
  const mag=new Float32Array(w*h);
  for(let y=y0;y<=y1;y++) for(let x=x0;x<=x1;x++){
    const p=y*w+x;
    const gx=-gray[p-w-1]+gray[p-w+1]-2*gray[p-1]+2*gray[p+1]-gray[p+w-1]+gray[p+w+1];
    const gy=-gray[p-w-1]-2*gray[p-w]-gray[p-w+1]+gray[p+w-1]+2*gray[p+w]+gray[p+w+1];
    const m=Math.hypot(gx,gy);mag[p]=m;mags.push(m);
  }
  mags.sort((a,b)=>a-b);
  const adaptive=mags[Math.floor(mags.length*.78)]||70;
  const threshold=Math.max(55,Math.min(120,adaptive));

  const out=hybrid.getContext("2d");
  const pixels=out.createImageData(w,h);
  for(let y=y0;y<=y1;y++) for(let x=x0;x<=x1;x++){
    const p=y*w+x;if(mag[p]<threshold) continue;
    let neighbours=0;
    for(let dy=-1;dy<=1;dy++) for(let dx=-1;dx<=1;dx++) if(dx||dy) if(mag[(y+dy)*w+x+dx]>=threshold) neighbours++;
    if(neighbours<2) continue;
    const i=p*4;pixels.data[i]=255;pixels.data[i+1]=255;pixels.data[i+2]=255;pixels.data[i+3]=235;
  }
  out.putImageData(pixels,0,0);
  return {threshold};
}

async function load(){
  if(!uuidLike(patternId)) throw new Error("invalid_pattern_id");
  const q=await supabase.from("photo_patterns_v2").select("id,name,target_key,reference_storage_path,active").eq("id",patternId).maybeSingle();
  if(q.error) throw q.error;
  const pattern=q.data;if(!pattern?.active||!pattern.reference_storage_path) throw new Error("pattern_not_available");
  title.textContent="Patrón: "+(pattern.target_key||pattern.name||"sin etiqueta");
  const d=await supabase.storage.from("photo-verification").download(pattern.reference_storage_path);
  if(d.error||!d.data) throw d.error||new Error("reference_download_failed");
  image.src=URL.createObjectURL(d.data);await image.decode();stage.hidden=false;
  status.textContent="Gemini está eligiendo la mejor referencia…";
  const result=await supabase.functions.invoke("generate-photo-pattern-guide",{body:{pattern_id:pattern.id}});
  if(result.error) throw result.error;
  const item=result.data?.landmarks?.[0];if(!result.data?.ok||!item) throw new Error(result.data?.error||"gemini_roi_failed");
  drawBox(item);
  const {threshold}=sobelPrimaryRoi(item);
  itemsList.replaceChildren();
  const li=document.createElement("li");li.textContent=item.label+" · utilidad "+item.alignment_score+"/100";itemsList.append(li);
  legend.hidden=false;
  status.textContent="Sobel listo · referencia: "+item.label+" · umbral "+Math.round(threshold);
}
load().catch(e=>{console.error("Gemini + Sobel failed",e);status.textContent="No se pudo generar la guía: "+(e?.message||"error desconocido");});
