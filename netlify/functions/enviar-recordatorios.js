// netlify/functions/enviar-recordatorios.js
// ---------------------------------------------------------------
// EJEMPLO del caso donde SÍ se necesita backend: usar un SECRETO real
// (service_role de Supabase y/o token de una API de mensajería).
// Estos valores viven en variables de entorno del SERVIDOR y NUNCA
// bajan al navegador, así que no aparecen en Ctrl + U.
//
// Configura en Netlify -> Environment variables:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE, WHATSAPP_TOKEN
// ---------------------------------------------------------------

const { createClient } = require("@supabase/supabase-js");

exports.handler = async (event) => {
  // Solo POST (método correcto para una acción que cambia/usa datos).
  if (event.httpMethod !== "POST") {
    return { statusCode: 405, body: "Método no permitido" };
  }

  // (Recomendado) protege este endpoint con un secreto compartido,
  // para que no lo dispare cualquiera desde internet.
  const auth = event.headers["x-tarea-token"];
  if (auth !== process.env.TAREA_TOKEN) {
    return { statusCode: 401, body: "No autorizado" };
  }

  // El cliente con service_role SOLO existe aquí, en el servidor.
  const sb = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE
  );

  // Ejemplo: traer deudores y enviarles recordatorio.
  const { data: regs, error } = await sb
    .from("registrations")
    .select("id, name, phone, total, payments(amount)");

  if (error) {
    return { statusCode: 500, body: JSON.stringify({ error: error.message }) };
  }

  const deudores = (regs || []).filter((r) => {
    const pagado = (r.payments || []).reduce((s, p) => s + p.amount, 0);
    return pagado < r.total;
  });

  // Aquí llamarías a tu API de WhatsApp/correo con el token secreto.
  // El token jamás se expone al navegador.
  // await fetch("https://api.tu-mensajeria.com/send", {
  //   method: "POST",
  //   headers: { Authorization: `Bearer ${process.env.WHATSAPP_TOKEN}` },
  //   body: JSON.stringify({ ... })
  // });

  return {
    statusCode: 200,
    body: JSON.stringify({ recordatorios: deudores.length }),
  };
};
