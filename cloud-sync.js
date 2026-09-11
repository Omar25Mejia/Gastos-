/* Sincronización cloud por usuario.
   La identidad la maneja Supabase Auth y RLS limita cada fila al usuario autenticado. */
(function(){
  const cfg=window.SUPABASE_CONFIG;
  if(!cfg?.url || !cfg?.anonKey || !window.supabase) return;
  const client=window.supabase.createClient(cfg.url,cfg.anonKey);
  const KEY='control-financiero-demo-v2';
  let syncing=false;
  let userId=null;

  async function pullOrSeed(user){
    userId=user.id;
    const {data,error}=await client.from('user_finance').select('data').eq('user_id',user.id).maybeSingle();
    if(error){ console.error('Cloud finance read:',error); return; }
    const local=localStorage.getItem(KEY);
    if(data?.data && Object.keys(data.data).length){
      localStorage.setItem(KEY,JSON.stringify(data.data));
      if(local && local!==JSON.stringify(data.data)) location.reload();
      return;
    }
    if(local){
      try{
        const parsed=JSON.parse(local);
        await client.from('user_finance').upsert({user_id:user.id,data:parsed},{onConflict:'user_id'});
      }catch(e){console.error('Cloud finance seed:',e);}
    }
  }

  const originalSetItem=Storage.prototype.setItem;
  Storage.prototype.setItem=function(key,value){
    originalSetItem.call(this,key,value);
    if(key===KEY && userId && !syncing){
      try{
        const parsed=JSON.parse(value);
        syncing=true;
        client.from('user_finance').upsert({user_id:userId,data:parsed},{onConflict:'user_id'})
          .then(({error})=>{if(error) console.error('Cloud finance save:',error);})
          .finally(()=>{syncing=false;});
      }catch(e){console.error('Cloud finance parse:',e);}
    }
  };

  client.auth.onAuthStateChange((event,session)=>{
    if(session?.user){
      setTimeout(()=>pullOrSeed(session.user),0);
    }else{
      userId=null;
    }
  });

  client.auth.getSession().then(({data})=>{
    if(data.session?.user) setTimeout(()=>pullOrSeed(data.session.user),0);
  });
})();
