module OfficeDocuments
  def office_document(ext, text: "Conteudo financeiro", slides: 1, macros: false)
    types = Lots::ExtractionService::OFFICE.fetch(ext)
    entries = {
      "[Content_Types].xml" => <<~XML,
        <?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/#{types.first}" ContentType="#{types.last}.main+xml"/></Types>
      XML
      "_rels/.rels" => '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="' + types.first + '"/></Relationships>'
    }
    if ext == ".docx"
      entries[types.first] = '<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>' + text + '</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Tabela orçamento</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr></w:body></w:document>'
    elsif ext == ".xlsx"
      entries[types.first] = '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Planilha" sheetId="1" r:id="rId1"/></sheets></workbook>'
      entries["xl/_rels/workbook.xml.rels"] = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
      entries["xl/worksheets/sheet1.xml"] = '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>' + text + '</t></is></c><c r="B1"><v>2025</v></c></row></sheetData></worksheet>'
    elsif ext == ".pptx"
      entries[types.first] = '<?xml version="1.0"?><p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>'
      slides.times do |i|
        entries["ppt/slides/slide#{i + 1}.xml"] = '<?xml version="1.0"?><p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><a:t>' + text + "</a:t></p:cSld></p:sld>"
      end
    else
      entries = { "mimetype" => types.last, "content.xml" => '<?xml version="1.0"?><office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"><office:body><draw:page><text:p>' + text + "</text:p></draw:page></office:body></office:document-content>" }
    end
    entries["word/vbaProject.bin"] = "macro" if macros
    zip_document(entries)
  end

  def zip_document(entries)
    Zip::OutputStream.write_buffer do |zip|
      entries.each do |name, value|
        zip.put_next_entry(name)
        zip.write(value)
      end
    end.string
  end
end
