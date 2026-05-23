import re

with open('CGF_ProjectHub-4-Cloud.html', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add CSS
css = """
/* FIREBASE AUTH & TEAM */
.auth-bg { background: rgba(0,0,0,0.85) !important; backdrop-filter: blur(8px); display: none; }
.auth-bg.open { display: flex !important; }
.team-table { width: 100%; border-collapse: collapse; margin-top: 1rem; font-size: 0.8rem; }
.team-table th, .team-table td { text-align: left; padding: 0.5rem; border-bottom: 1px solid var(--border); }
.team-table th { color: var(--fg2); font-weight: 600; }
.ro-disabled { opacity: 0.4; pointer-events: none; }
.hide-guest { display: none; }
"""
content = content.replace('</style>', css + '\n</style>')

# 2. Header buttons
header_search = """<button class="btn btn-icon btn-ghost" onclick="exportJSON()" title="Backup JSON">💾</button>
    <button class="btn" onclick="importData()">↑ Importar</button>
    <button class="btn btn-accent" onclick="openModal('m-sys')">+ Sistema</button>"""
header_replace = """<button class="btn btn-icon btn-ghost" onclick="exportJSON()" title="Backup JSON">💾</button>
    <button class="btn auth-owner" id="btn-team" style="display:none;" onclick="openModal('m-team')">👥 Equipa</button>
    <button class="btn" onclick="window.logoutUser()">Sair</button>
    <button class="btn btn-accent auth-write" id="btn-add-sys" onclick="openModal('m-sys')">+ Sistema</button>"""
content = content.replace(header_search, header_replace)

# 3. Modals
modals = """
<!-- MODAL: LOGIN -->
<div class="modal-bg auth-bg" id="m-login" style="z-index: 9999;">
  <div class="modal">
    <div class="modal-h"><h2>Entrar no Project Hub</h2></div>
    <div class="modal-b">
      <div class="g1" style="gap:1rem;">
        <div><label class="lbl">E-mail</label><input type="email" id="auth-email" class="inp" placeholder="dino@got.com"></div>
        <div><label class="lbl">Senha</label><input type="password" id="auth-pass" class="inp" placeholder="••••••••"></div>
        <div style="display:flex;gap:0.5rem;margin-top:0.5rem;">
          <button class="btn btn-accent" style="flex:1;" onclick="window.loginUser()">Entrar</button>
          <button class="btn" style="flex:1;" onclick="window.registerUser()">Criar Conta</button>
        </div>
        <div id="auth-error" style="color:var(--red);font-size:0.8rem;text-align:center;margin-top:0.5rem;"></div>
      </div>
    </div>
  </div>
</div>

<!-- MODAL: TEAM -->
<div class="modal-bg" id="m-team">
  <div class="modal" style="max-width:600px;">
    <div class="modal-h">
      <h2>Gestão da Equipa</h2>
      <button class="btn btn-sm btn-icon" onclick="closeModal('m-team')">✕</button>
    </div>
    <div class="modal-b">
      <table class="team-table">
        <thead><tr><th>Email</th><th>Função</th><th>Último Acesso</th><th>Ações</th></tr></thead>
        <tbody id="team-list"></tbody>
      </table>
    </div>
  </div>
</div>
"""
content = content.replace('<div class="toast" id="toast"></div>', '<div class="toast" id="toast"></div>\n' + modals)

# 4. Rewrite save and load
save_load_search = """function save(){try{localStorage.setItem('cgf2',JSON.stringify(D));updateSidebarCounts();}catch(e){if(e.name==='QuotaExceededError')toast('⚠ Armazenamento cheio! Exporta os dados como backup.');}}
function load(){try{const s=localStorage.getItem('cgf2');if(s)D=JSON.parse(s);}catch(e){}}"""
save_load_replace = """function save(){ updateSidebarCounts(); if(window.cloudSave) window.cloudSave(D); }
function load(){ /* Handled by Firebase */ }"""
content = content.replace(save_load_search, save_load_replace)

# 5. Disable ESC for login modal
content = content.replace(
    "if(e.key==='Escape'){document.querySelectorAll('.modal-bg.open').forEach(m=>m.classList.remove('open'));",
    "if(e.key==='Escape'){document.querySelectorAll('.modal-bg.open:not(#m-login)').forEach(m=>m.classList.remove('open'));"
)

# 6. Add Firebase module script at the end
firebase_script = """
<script type="module">
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.8.1/firebase-app.js";
import { getAuth, signInWithEmailAndPassword, createUserWithEmailAndPassword, onAuthStateChanged, signOut } from "https://www.gstatic.com/firebasejs/10.8.1/firebase-auth.js";
import { getFirestore, doc, getDoc, setDoc, onSnapshot, collection, getDocs, updateDoc } from "https://www.gstatic.com/firebasejs/10.8.1/firebase-firestore.js";

const firebaseConfig = {
  apiKey: "AIzaSyDWOlV0QnecMwW60ix4ZOu86wCywrC9vLc",
  authDomain: "cgf-projecthub.firebaseapp.com",
  projectId: "cgf-projecthub",
  storageBucket: "cgf-projecthub.firebasestorage.app",
  messagingSenderId: "592638617488",
  appId: "1:592638617488:web:25cc7ff0c679d8c814f515"
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

let currentRole = 'guest';

window.loginUser = async () => {
  const e=document.getElementById('auth-email').value, p=document.getElementById('auth-pass').value;
  try{ await signInWithEmailAndPassword(auth, e, p); document.getElementById('auth-error').textContent=''; }
  catch(err){ document.getElementById('auth-error').textContent="Email ou senha inválidos."; }
};

window.registerUser = async () => {
  const e=document.getElementById('auth-email').value, p=document.getElementById('auth-pass').value;
  try{ 
    const res = await createUserWithEmailAndPassword(auth, e, p);
    await setDoc(doc(db, "users", res.user.uid), { email: e, role: 'guest', status: 'active', last_online: new Date().toISOString() });
    document.getElementById('auth-error').textContent='';
  }catch(err){ document.getElementById('auth-error').textContent="Erro ao criar conta: "+err.message; }
};

window.logoutUser = async () => { await signOut(auth); };

onAuthStateChanged(auth, async (user) => {
  const mLogin = document.getElementById('m-login');
  if(!user){
    mLogin.classList.add('open');
    document.querySelectorAll('.auth-write, .auth-owner').forEach(el=>el.style.display='none');
    return;
  }
  
  // User logged in
  const udoc = await getDoc(doc(db, "users", user.uid));
  let udata = udoc.data();
  if(!udata){ 
    // Failsafe for manually created users via console
    udata = { email: user.email, role: 'guest', status: 'active', last_online: new Date().toISOString() };
    await setDoc(doc(db, "users", user.uid), udata);
  }
  
  if(udata.status === 'banned'){
    document.getElementById('auth-error').textContent="Esta conta foi banida.";
    await signOut(auth);
    return;
  }
  
  // Success
  mLogin.classList.remove('open');
  currentRole = udata.role;
  
  // Update last online
  await updateDoc(doc(db, "users", user.uid), { last_online: new Date().toISOString() });
  
  // Apply role UI
  if(currentRole === 'owner') document.querySelectorAll('.auth-owner').forEach(el=>el.style.display='inline-flex');
  else document.querySelectorAll('.auth-owner').forEach(el=>el.style.display='none');
  
  if(currentRole === 'owner' || currentRole === 'dev'){
    document.querySelectorAll('.auth-write').forEach(el=>el.style.display='inline-flex');
  } else {
    document.querySelectorAll('.auth-write').forEach(el=>el.style.display='none');
    toast("Modo Visitante: Apenas leitura.");
  }
  
  // Load Team if owner
  if(currentRole === 'owner') loadTeam();

  // Listen to remote data
  onSnapshot(doc(db, "projects", "cgf"), (dSnap) => {
    if(dSnap.exists()){
      D = dSnap.data();
      if(!D.nid) D.nid=100;
      if(!D.systems) D.systems=[];
      if(!D.assets) D.assets=[];
      if(!D.timeline) D.timeline=[];
      if(!D.decisions) D.decisions=[];
      renderDash(); updateSidebarCounts();
      const st=document.getElementById('sys-search'); if(st) renderSys(sysFilter, st.value);
      renderModel(); renderTL(); renderDec();
    } else {
      // First time init
      window.cloudSave(D);
    }
  });
});

window.cloudSave = async (data) => {
  if(currentRole !== 'owner' && currentRole !== 'dev') return; // Guests can't save
  try {
    await setDoc(doc(db, "projects", "cgf"), data);
  } catch(e) {
    console.error("Cloud save error", e);
    toast("Erro ao guardar na nuvem!");
  }
};

async function loadTeam(){
  const snap = await getDocs(collection(db, "users"));
  const html = [];
  snap.forEach(d => {
    const u = d.data();
    const id = d.id;
    const dStr = new Date(u.last_online).toLocaleString('pt-PT');
    html.push(`<tr>
      <td>${u.email}</td>
      <td>
        <select class="inp" style="padding:0.2rem;font-size:0.75rem;" onchange="window.changeRole('${id}', this.value)">
          <option value="guest" ${u.role==='guest'?'selected':''}>Visitante</option>
          <option value="dev" ${u.role==='dev'?'selected':''}>Dev</option>
          <option value="owner" ${u.role==='owner'?'selected':''}>Dono</option>
        </select>
      </td>
      <td>${dStr}</td>
      <td>
        <button class="btn btn-sm ${u.status==='banned'?'btn-accent':'btn-danger'}" onclick="window.toggleBan('${id}', '${u.status}')">
          ${u.status==='banned'?'Desbanir':'Banir'}
        </button>
      </td>
    </tr>`);
  });
  document.getElementById('team-list').innerHTML = html.join('');
}

window.changeRole = async (uid, newRole) => {
  await updateDoc(doc(db, "users", uid), { role: newRole });
  toast("Função actualizada.");
};

window.toggleBan = async (uid, currStatus) => {
  const ns = currStatus === 'banned' ? 'active' : 'banned';
  await updateDoc(doc(db, "users", uid), { status: ns });
  toast("Estado actualizado.");
  loadTeam();
};
</script>
"""
content = content.replace('</body>', firebase_script + '\n</body>')

with open('CGF_ProjectHub-4-Cloud.html', 'w', encoding='utf-8') as f:
    f.write(content)

