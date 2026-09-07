import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
test('native translations cover all UI keys and preserve format arguments', {skip:process.platform!=='darwin'},()=>{
 const dicts=Object.fromEntries(['ru','en','he','es'].map(lang=>[lang,JSON.parse(execFileSync('plutil',['-convert','json','-o','-',new URL('../../../TorBooking/'+lang+'.lproj/Localizable.strings',import.meta.url).pathname],{encoding:'utf8'}))]));
 const formats=s=>(s.match(/%(?:@|d)/g)||[]).sort();
 for(const lang of ['en','he','es']){
  assert.deepEqual(Object.keys(dicts[lang]).sort(),Object.keys(dicts.ru).sort());
  for(const [key,value] of Object.entries(dicts[lang])){
   assert(value.trim());assert.deepEqual(formats(value),formats(key),lang+': '+key);
   assert(!/[А-Яа-яЁё]/.test(value),lang+': '+key);
  }
 }
 for(const file of ['App.swift','ContentView.swift','LiveBusinessView.swift']){
  const source=readFileSync(new URL('../../../TorBooking/'+file,import.meta.url),'utf8');
  for(const match of source.matchAll(/\bL\("([^"]+)"/g)) assert(dicts.ru[match[1]],'Missing translation: '+match[1]);
 }
});
