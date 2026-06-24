// Dump every attachment (request/response captures, DB rows before/after) from a trace dir.
import fs from 'node:fs';
const dir = process.argv[2];
const label = process.argv[3] ?? dir;
console.log('\n########## ' + label);
for (const tf of fs.readdirSync(dir).filter((f) => f.endsWith('.trace'))) {
  for (const line of fs.readFileSync(dir + '/' + tf, 'utf8').split('\n')) {
    if (!line) continue;
    let e; try { e = JSON.parse(line); } catch { continue; }
    const atts = e.attachments ?? (e.type === 'attach' ? [e] : []);
    for (const a of atts) {
      if (!a.name || a.name === 'trace') continue;
      let body = '';
      if (a.sha1 && fs.existsSync(dir + '/resources/' + a.sha1)) body = fs.readFileSync(dir + '/resources/' + a.sha1, 'utf8');
      else if (a.body) body = Buffer.from(a.body, 'base64').toString('utf8');
      console.log('--- ' + a.name + ':');
      console.log(body.length > 800 ? body.slice(0, 800) + ' …' : body);
    }
  }
}
