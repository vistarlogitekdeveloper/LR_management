const fs=require('fs');
const d=JSON.parse(fs.readFileSync("C:/Users/Admin/Downloads/SCT External APIs.postman_collection.json","utf8"));
console.log("TOP KEYS:",Object.keys(d));
console.log("INFO:",JSON.stringify(d.info));
function walk(items,depth,path){
  for(const it of items){
    const p=path+"/"+it.name;
    if(it.item){
      console.log("  ".repeat(depth)+"[FOLDER] "+it.name+"  descLen="+((it.description&&(it.description.content||it.description))||"").length);
      walk(it.item,depth+1,p);
    } else {
      const r=it.request||{};
      console.log("  ".repeat(depth)+"[REQ] "+it.name+" | "+(r.method||"?")+" "+((r.url&&r.url.raw)||"")+" | responses="+((it.response||[]).length)+" | descLen="+(((r.description&&(r.description.content||r.description))||"")).length);
    }
  }
}
walk(d.item,0,"");
