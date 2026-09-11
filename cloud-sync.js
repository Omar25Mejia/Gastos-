/* Sincronización cloud por usuario.
   La identidad la maneja Supabase Auth y RLS limita cada fila al usuario autenticado. */
(function(){
  const cfg=window.SUPABASE_CONFIG;
  if(!cfg?.url || !cfg?.anonKey || !window.supabase) return;
  const client=window.supabase.createClient(cfg.url,cfg.anonKey);
  const KEY='control-financiero-demo-v2';
  const ACCOUNT_MARK='cf-account-initialized';
  let syncing=false;
  let userId=null;

  function emptyFinance(){
    return {debts:[],payments:[],incomes:[],expenses:[],settings:{salary:0,extraAverage:0,cashReserve:0,goalDate:'2026-12-31'}};
  }

  async function pullOrSeed(user){
    userId=user.id;
    const {data,error}=await client.from('user_finance').select('data').eq('user_id',user.id).maybeSingle();
    if(error){ console.error('Cloud finance read:',error); return; }
    const local=localStorage.getItem(KEY);
    if(data?.data && Object.keys(data.data).length){
      const remote=JSON.stringify(data.data);
      localStorage.setItem(KEY,remote);
      localStorage.setItem(ACCOUNT_MARK,'1');
      if(local && local!==remote) location.reload();
      return;
    }

    // En la primera cuenta, si el frontend todavía tiene el estado inicial en memoria,
    // lo migramos a la cuenta recién creada. Las cuentas posteriores empiezan limpias.
    if(!localStorage.getItem(ACCOUNT_MARK)){
      try{
        const initial=(local && JSON.parse(local)) || (typeof db !== 'undefined' ? db : null);
        if(initial && Array.isArray(initial.debts) && initial.debts.length){
          const {error:seedError}=await client.from('user_finance').upsert({user_id:user.id,data:initial},{onConflict:'user_id'});
          if(seedError) throw seedError;
          localStorage.setItem(KEY,JSON.stringify(initial));
          localStorage.setItem(ACCOUNT_MARK,'1');
          location.reload();
          return;
        }
      }catch(e){console.error('Cloud finance seed:',e);}
    }

    const clean=emptyFinance();
    localStorage.setItem(KEY,JSON.stringify(clean));
    localStorage.setItem(ACCOUNT_MARK,'1');
    location.reload();
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
    if(session?.user) setTimeout(()=>pullOrSeed(session.user),0);
    else userId=null;
  });

  client.auth.getSession().then(({data})=>{
    if(data.session?.user) setTimeout(()=>pullOrSeed(data.session.user),0);
  });
})();
