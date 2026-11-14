let pdfLibrary;
function offlinePdfLibrary() {
 if (!pdfLibrary) {
  const moduleUrl = encoded => URL.createObjectURL(new Blob(
   [Uint8Array.from(atob(encoded), ch => ch.charCodeAt(0))], {type:'text/javascript'}));
  pdfLibrary = import(moduleUrl(pdfBundle.main)).then(lib => {
   lib.GlobalWorkerOptions.workerSrc = moduleUrl(pdfBundle.worker);
   return lib;
  });
 }
 return pdfLibrary;
}
class OfflinePdfResources {
 async fetch({filename}) {
  const encoded=pdfBundle.assets[filename];
  if(typeof encoded!=='string')throw Error('Missing PDF resource');
  return Uint8Array.from(atob(encoded), ch=>ch.charCodeAt(0));
 }
}
async function renderPdfPage(doc,num,limit) {
 const page=await doc.getPage(num);
 const size=page.getViewport({scale:1});
 const viewport=page.getViewport({scale:Math.min(limit/Math.max(size.width,size.height),4)});
 const canvas=document.createElement('canvas');
 canvas.width=Math.max(1,Math.ceil(viewport.width));canvas.height=Math.max(1,Math.ceil(viewport.height));
 await page.render({canvas,viewport}).promise;
 return canvas;
}
async function pickPdfPage(doc,name) {
 if(doc.numPages===1)return 1;
 const dialog=$('pdfPicker'), field=$('pageNumber'), preview=$('pagePreview'), use=$('usePage');
 let revision=0;
 async function update() {
  const rev=++revision, n=field.valueAsNumber;
  use.disabled=true;preview.replaceChildren();
  if(!field.validity.valid||!Number.isInteger(n))return;
  try {
   const canvas=await renderPdfPage(doc,n,720);
   if(rev===revision&&dialog.open){preview.replaceChildren(canvas);use.disabled=false}
  } catch {if(rev===revision) preview.textContent='このページを表示できません。'}
 }
 field.max=doc.numPages;field.value=1;field.oninput=update;
 $('pageCount').textContent=' / '+doc.numPages+' ページ';$('pdfName').textContent=name;
 dialog.returnValue='';dialog.showModal();update();
 await new Promise(resolve=>dialog.addEventListener('close',resolve,{once:true}));
 revision++;preview.replaceChildren();field.oninput=null;
 return dialog.returnValue==='use'?field.valueAsNumber:null;
}
async function importMedia(file) {
 if(file.type!=='application/pdf'&&!/\.pdf$/i.test(file.name))return {name:file.name,src:await read(file,'readAsDataURL')};
 const lib=await offlinePdfLibrary();
 const task=lib.getDocument({data:new Uint8Array(await file.arrayBuffer()),BinaryDataFactory:OfflinePdfResources,
  useWorkerFetch:false,cMapPacked:true,isEvalSupported:false,useSystemFonts:true});
 try {
  const doc=await task.promise;
  const n=await pickPdfPage(doc,file.name);
  if(n===null)return null;
  const canvas=await renderPdfPage(doc,n,3500);
  return {name:file.name+'（'+n+'ページ）',src:canvas.toDataURL('image/png')};
 } finally {await task.destroy()}
}
