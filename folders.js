const fs=require('fs');
const d=JSON.parse(fs.readFileSync("C:/Users/Admin/Downloads/SCT External APIs.postman_collection.json","utf8"));
const D=x=>x?(x.content||x):"";
function walk(items,path){
  for(const it of items){
    if(it.item){
      console.log("\n================ FOLDER: "+path+"/"+it.name+" ================");
      console.log(D(it.description));
      walk(it.item,path+"/"+it.name);
    }
  }
}
walk(d.item,"");
console.log("\n================ COLLECTION auth ================");
console.log(JSON.stringify(d.auth,null,1));
console.log("\n================ COLLECTION variables ================");
console.log(JSON.stringify(d.variable,null,1));
console.log("\n================ COLLECTION events ================");
console.log(JSON.stringify(d.event,null,1));
