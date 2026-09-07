'use strict';
const $ = id => document.getElementById(id);
const words = {
 es:{loading:'Cargando...',retry:'Reintentar',unavailable:'Esta página de reservas no está disponible.',serviceTitle:'Elige un servicio',service:'Servicio',staff:'Profesional',when:'Día y hora',details:'Tus datos',name:'Nombre completo',phone:'Teléfono con prefijo de país',consent:'Compartir mi nombre y teléfono con este negocio para gestionar mi cita.',submit:'Solicitar cita',success:'Solicitud recibida',pending:'Tu cita está pendiente de confirmación del negocio.',changes:'Para cambiar o cancelar la cita, contacta con el negocio.',call:'Llamar',whatsapp:'WhatsApp',empty:'No hay servicios disponibles.',noSlots:'No hay horas libres este día. Elige otro día.',times:'Elige una hora',zone:'Zona horaria del negocio',failed:'No se pudo conectar. Inténtalo de nuevo.',conflict:'Esta hora ya no está disponible. Elige otra.',invalid:'Revisa tus datos y la fecha seleccionada.',limit:'Demasiadas solicitudes. Inténtalo de nuevo en 15 minutos.',minutes:'min',prev:'Mes anterior',next:'Mes siguiente'},
 en:{loading:'Loading...',retry:'Retry',unavailable:'This booking page is unavailable.',serviceTitle:'Choose a service',service:'Service',staff:'Specialist',when:'Day and time',details:'Your details',name:'Full name',phone:'Phone with country code',consent:'Share my name and phone with this business to manage my appointment.',submit:'Request appointment',success:'Request received',pending:'Your appointment is awaiting confirmation from the business.',changes:'To change or cancel, contact the business.',call:'Call',whatsapp:'WhatsApp',empty:'No services available for booking.',noSlots:'No free times on this day. Choose another day.',times:'Choose a time',zone:'Business timezone',failed:'Unable to connect. Please try again.',conflict:'This time is no longer available. Choose another time.',invalid:'Check your details and selected date.',limit:'Too many requests. Please try again in 15 minutes.',minutes:'min',prev:'Previous month',next:'Next month'},
 he:{loading:'טוען...',retry:'ניסיון נוסף',unavailable:'עמוד ההזמנות אינו זמין.',serviceTitle:'בחירת שירות',service:'שירות',staff:'איש צוות',when:'יום ושעה',details:'הפרטים שלך',name:'שם מלא',phone:'טלפון כולל קידומת מדינה',consent:'אני מסכים לשתף שם וטלפון עם העסק לצורך ניהול התור.',submit:'בקשת תור',success:'הבקשה התקבלה',pending:'התור ממתין לאישור העסק.',changes:'לשינוי או ביטול יש לפנות לעסק.',call:'טלפון',whatsapp:'WhatsApp',empty:'אין שירותים זמינים להזמנה.',noSlots:'אין שעות פנויות ביום זה. בחרו יום אחר.',times:'בחרו שעה',zone:'אזור הזמן של העסק',failed:'לא ניתן להתחבר. נסו שוב.',conflict:'השעה כבר תפוסה. בחרו שעה אחרת.',invalid:'בדקו את הפרטים והתאריך.',limit:'יותר מדי בקשות. נסו שוב בעוד 15 דקות.',minutes:'דקות',prev:'החודש הקודם',next:'החודש הבא'},
 ru:{loading:'Загрузка…',retry:'Повторить',unavailable:'Страница записи недоступна.',serviceTitle:'Выбери услугу',service:'Услуга',staff:'Специалист',when:'День и время',details:'Твои данные',name:'Имя и фамилия',phone:'Телефон с кодом страны',consent:'Передать моё имя и телефон этому бизнесу для управления записью.',submit:'Записаться',success:'Заявка принята',pending:'Запись ожидает подтверждения бизнеса.',changes:'Для переноса или отмены свяжись с бизнесом.',call:'Позвонить',whatsapp:'WhatsApp',empty:'Пока нет доступных услуг.',noSlots:'На этот день свободного времени нет. Выбери другой день.',times:'Выбери время',zone:'Часовой пояс бизнеса',failed:'Не удалось подключиться. Попробуй ещё раз.',conflict:'Это время уже занято. Выбери другое.',invalid:'Проверь данные и выбранную дату.',limit:'Слишком много запросов. Попробуй через 15 минут.',minutes:'мин',prev:'Предыдущий месяц',next:'Следующий месяц'}
};
let lang = 'en', profile, today, latest, selectedDay, month, slot = '', slots = [], busy = false, done = false;
let revision = 0, slotState = '', requestKey = '', lastPayload = '', receipt;
const endpoint = '/v1/public/' + encodeURIComponent(location.pathname.split('/').filter(Boolean).pop());
const t = key => words[lang][key];
const localDate = value => new Date(value + 'T12:00:00Z');
const dateKey = date => date.toISOString().slice(0,10);
const formatDate = value => new Intl.DateTimeFormat(lang,{dateStyle:'full',timeZone:'UTC'}).format(localDate(value));
const time = value => new Intl.DateTimeFormat(lang,{hour:'2-digit',minute:'2-digit',hour12:false,timeZone:profile.business.timezone}).format(new Date(value));
const money = minor => new Intl.NumberFormat(lang,{style:'currency',currency:profile.business.currency}).format(minor/100);
function text(id, value) { $(id).textContent = value; }
async function api(path, options) {
 const response = await fetch(endpoint+path, {headers:{'Content-Type':'application/json'},...options});
 const data = await response.json();
 if (!response.ok) { const error = new Error(data.error); error.status=response.status; throw error; }
 return data;
}
function message(error) { return t(error.status===404?'unavailable':error.status===409?'conflict':error.status===400?'invalid':error.status===429?'limit':'failed'); }
function translate() {
 document.documentElement.lang=lang;
 document.documentElement.dir=lang==='he'?'rtl':'ltr';
 document.querySelectorAll('[data-i18n]').forEach(el=>el.textContent=t(el.dataset.i18n));
 $('previous').ariaLabel=t('prev'); $('next').ariaLabel=t('next');
 text('retry',t('retry'));
 if (!profile) return;
 text('call',t('call'));text('whatsapp',t('whatsapp'));
 text('timezone',t('zone')+': '+profile.business.timezone);
 for (const option of $('service').options) {
  const service=profile.services.find(s=>s.id===option.value);
  option.textContent=service.name+' · '+money(service.price_minor)+' · '+service.minutes+' '+t('minutes');
 }
 renderCalendar();renderSlots();summary();
 if (done) renderReceipt();
}
function renderCalendar() {
 const first=localDate(month+'-01'), year=first.getUTCFullYear(), m=first.getUTCMonth();
 text('month-title',new Intl.DateTimeFormat(lang,{month:'long',year:'numeric',timeZone:'UTC'}).format(first));
 $('previous').disabled=month<=today.slice(0,7)||busy;
 $('next').disabled=month>=latest.slice(0,7)||busy;
 $('weekdays').replaceChildren();
 for(let i=0;i<7;i++) {
  const label=document.createElement('span');
  label.textContent=new Intl.DateTimeFormat(lang,{weekday:'short',timeZone:'UTC'}).format(new Date(Date.UTC(2026,0,4+i)));
  $('weekdays').append(label);
 }
 $('days').replaceChildren();
 for(let i=0;i<first.getUTCDay();i++) $('days').append(document.createElement('span'));
 const count=new Date(Date.UTC(year,m+1,0)).getUTCDate();
 for(let d=1;d<=count;d++) {
  const key=dateKey(new Date(Date.UTC(year,m,d))), button=document.createElement('button');
  button.type='button';button.textContent=d;button.disabled=key<today||key>latest||busy;
  button.ariaLabel=formatDate(key);button.setAttribute('aria-pressed',String(key===selectedDay));
  if(key===selectedDay) button.className='selected';
  button.addEventListener('click',()=>{selectedDay=key;slot='';renderCalendar();loadSlots();});
  $('days').append(button);
 }
 text('selected-date',formatDate(selectedDay));
}
function renderSlots() {
 $('slots').replaceChildren();
 text('slot-status',slotState ? t(slotState) : (slots.length ? t('times') : t('noSlots')));
 for(const value of slots) {
  const button=document.createElement('button');
  button.type='button';button.textContent=time(value);button.disabled=busy;
  button.setAttribute('aria-pressed',String(slot===value));
  if(slot===value) button.className='selected';
  button.onclick=()=>{slot=value;renderSlots();summary();};
  $('slots').append(button);
 }
 summary();
}
function summary() {
 const service=profile?.services.find(s=>s.id===$('service').value);
 text('summary',service&&slot ? service.name+' · '+formatDate(selectedDay)+' · '+time(slot)+' · '+money(service.price_minor) : '');
 $('submit').disabled=busy||!slot||!service||!$('staff').value;
}
async function loadSlots() {
 const current=++revision;
 slot='';slots=[];slotState='loading';renderSlots();
 if(!$('service').value||!$('staff').value) {slotState='noSlots';renderSlots();return;}
 try {
  const query=new URLSearchParams({serviceId:$('service').value,staffId:$('staff').value,date:selectedDay});
  const data=await api('/availability?'+query);
  if(current!==revision) return;
  slots=data.slots;slotState='';
 } catch(error) {if(current!==revision) return;slotState=error.status===429?'limit':'failed';}
 renderSlots();
}
function moveMonth(delta) {
 const d=localDate(month+'-01');d.setUTCMonth(d.getUTCMonth()+delta);
 month=dateKey(d).slice(0,7);renderCalendar();
}
function renderReceipt() {
 const date=new Intl.DateTimeFormat(lang,{dateStyle:'full',timeStyle:'short',timeZone:profile.business.timezone}).format(new Date(receipt.starts_at));
 text('receipt',receipt.service_name+' · '+date+' · '+profile.business.timezone);
 text('contact-again',profile.business.phone);
}
async function load() {
 text('status',t('loading'));$('retry').hidden=true;
 try {
  profile=await api('');
  let preferred = navigator.language.slice(0,2);
  try { preferred = localStorage.getItem('torly.booking.language') || preferred; } catch {}
  lang=Object.hasOwn(words,preferred) ? preferred : (Object.hasOwn(words,profile.business.locale) ? profile.business.locale : 'en');
  $('language').value=lang;
  const business=profile.business;
  text('business-name',business.name);text('address',business.address);
  document.title=business.name+' | Torly';
  $('call').href='tel:'+business.phone;
  $('contact-again').href='tel:'+business.phone;
  $('whatsapp').href='https://wa.me/'+business.phone.replace(/\D/g,'');
  $('waze').href='https://waze.com/ul?q='+encodeURIComponent(business.address)+'&navigate=yes';
  $('service').replaceChildren(...profile.services.map(s=>new Option(s.name,s.id)));
  $('staff').replaceChildren(...profile.staff.map(s=>new Option(s.name,s.id)));
  today=new Intl.DateTimeFormat('en-CA',{year:'numeric',month:'2-digit',day:'2-digit',timeZone:business.timezone}).format(new Date());
  const parts=new Intl.DateTimeFormat('en',{year:'numeric',month:'2-digit',day:'2-digit',timeZone:business.timezone}).formatToParts(new Date());
  today=['year','month','day'].map(type=>parts.find(p=>p.type===type).value).join('-');
  const max=localDate(today);max.setUTCDate(max.getUTCDate()+180);latest=dateKey(max);
  selectedDay=today;month=today.slice(0,7);
  $('profile').hidden=false;$('status').hidden=true;
  translate();
  if(!profile.services.length||!profile.staff.length) {
   $('booking-form').hidden=true;$('status').hidden=false;text('status',t('empty'));return;
  }
  await loadSlots();
 } catch(error) {text('status',message(error));$('retry').hidden=false;}
}
$('language').onchange=()=>{lang=$('language').value;try {localStorage.setItem('torly.booking.language',lang);} catch {} translate();};
$('previous').onclick=()=>moveMonth(-1);$('next').onclick=()=>moveMonth(1);
$('service').onchange=loadSlots;$('staff').onchange=loadSlots;$('retry').onclick=load;
$('booking-form').onsubmit=async event=>{
 event.preventDefault();
 if(busy||!slot||!$('booking-form').reportValidity()) return;
 const payload={serviceId:$('service').value,staffId:$('staff').value,startsAt:slot,
  clientName:$('client-name').value.trim(),clientPhone:$('phone').value.trim()};
 const fingerprint=JSON.stringify(payload);
 if(fingerprint!==lastPayload) {requestKey=crypto.randomUUID();lastPayload=fingerprint;}
 busy=true;text('error','');
 for(const control of $('booking-form').elements) control.disabled=true;
 try {
  const data=await api('/bookings',{method:'POST',body:JSON.stringify({...payload,requestKey})});
  done=true;receipt=data.booking;$('booking-form').hidden=true;$('success').hidden=false;renderReceipt();
  $('success').scrollIntoView({behavior:'smooth',block:'start'});
 } catch(error) {
  text('error',message(error));
  if(error.status===409) await loadSlots();
 } finally {
  busy=false;
  for(const control of $('booking-form').elements) control.disabled=false;
  renderCalendar();renderSlots();summary();
 }
};
load();
