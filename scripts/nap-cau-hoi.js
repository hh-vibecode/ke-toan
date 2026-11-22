// Nạp câu hỏi "Cần giải đáp" từ kt-cau-hoi.local.json (gitignore — có số liệu thật) vào kt_cau_hoi.
// Chỉ THÊM câu chưa có (so theo tiêu đề) — không đụng câu đã trả lời. Monsieur Claude
const fs = require('fs'), path = require('path'); const { sql } = require('./sql');
(async () => {
  const ds = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'kt-cau-hoi.local.json'), 'utf8'))
    .map((c, i) => ({ thu_tu: (i + 1) * 10, nhom: c.nhom, hoi_ai: c.hoi_ai || 'ke_toan', tieu_de: c.tieu_de, giai_thich: c.giai_thich, lua_chon: c.lua_chon || [] }));
  const r = await sql(`with x as (select * from jsonb_to_recordset($kt$${JSON.stringify(ds)}$kt$::jsonb)
      as t(thu_tu int, nhom text, hoi_ai text, tieu_de text, giai_thich text, lua_chon jsonb))
    insert into kt_cau_hoi (thu_tu, nhom, hoi_ai, tieu_de, giai_thich, lua_chon)
    select thu_tu, nhom, hoi_ai, tieu_de, giai_thich, array(select jsonb_array_elements_text(lua_chon)) from x
     where not exists (select 1 from kt_cau_hoi c where c.tieu_de = x.tieu_de) returning id`);
  console.log('Đã thêm', r.length, 'câu hỏi');
})().catch(e => { console.error(e.message); process.exit(1); });
