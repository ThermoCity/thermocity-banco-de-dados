// =============================================================================
// ThermoCity — Épico 83 · relatórios no MongoDB
// Rodar depois da carga:  mongosh "<sua conexão>" mongodb/02_relatorios.js
// As consultas equivalentes no Oracle estão em sql/regras/08_relatorios_oracle.sql.
// =============================================================================

db = db.getSiblingDB("thermocity");   // equivale a "use thermocity"

// 0) Correspondência: um documento para cada linha das tabelas de origem
print("== 0) Correspondência Oracle -> MongoDB ==");
printjson({
  setores: db.setores.countDocuments({}),                           // = COUNT(*) TMC_SETOR (420)
  setores_com_calor: db.setores.countDocuments({ calor: { $ne: null } }), // = COUNT(*) TMC_CALOR_SETOR (420)
  servicos: db.servicos.countDocuments({})                          // = COUNT(*) TMC_SERVICO (191)
});

// 1) AGREGAÇÃO — setores e população idosa por nota de calor
print("== 1) Setores e população 60+ por nota de calor (aggregate) ==");
db.setores.aggregate([
  { $match: { "calor.classe": { $ne: null } } },
  { $group: {
      _id: "$calor.classe",
      setores: { $sum: 1 },
      idosos_60_mais: { $sum: "$populacao.idosos_60_mais" },
      idosos_70_mais: { $sum: "$populacao.p70_mais" },
      lst_media_c: { $avg: "$calor.lst_verao_c" }
  } },
  { $project: { _id: 0, nota_calor: "$_id", setores: 1, idosos_60_mais: 1, idosos_70_mais: 1,
                lst_media_c: { $round: ["$lst_media_c", 2] } } },
  { $sort: { nota_calor: 1 } }
]).forEach(printjson);

// 2) CONSULTA — refúgios públicos confirmados (os que o roteiro de IA pode sugerir)
print("== 2) Refúgios públicos confirmados (find) ==");
db.servicos.find(
  { tipo: "REFUGIO", revisao: "manter" },
  { _id: 0, nome: 1, categoria: 1, bairro: 1 }
).sort({ nome: 1 }).forEach(printjson);

// 3) CONSULTA — setores críticos: nota de calor 5 e IPVS 4 ou mais, com mais idosos 70+
print("== 3) Top 10 setores críticos por pessoas 70+ (find) ==");
db.setores.find(
  { "calor.classe": 5, "ipvs.grupo": { $gte: 4 } },
  { codigo: "$_id", _id: 0, ipvs: "$ipvs.grupo", p70_mais: "$populacao.p70_mais",
    p60_69: "$populacao.p60_69", lst_c: { $round: ["$calor.lst_verao_c", 1] } }
).sort({ "populacao.p70_mais": -1, _id: 1 }).limit(10).forEach(printjson);
