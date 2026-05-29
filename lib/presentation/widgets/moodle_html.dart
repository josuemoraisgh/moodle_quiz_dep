// Re-exporta o renderer de HTML do Moodle (com suporte a LaTeX, imagens
// autenticadas, filtros de assets decorativos…) usado nas páginas de
// professor para que a página do aluno possa renderizar exatamente o
// mesmo conteúdo, garantindo paridade visual entre as duas vistas.
export '../pages/professor/professor_reveal_page.dart' show MoodleHtml;
