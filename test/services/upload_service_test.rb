require "test_helper"
class UploadServiceTest < ActiveSupport::TestCase
  setup { @user = create_user }

  test "upload é pending e enfileira job sem processar; duplicados aceitos" do
    assert_enqueued_jobs 2, only: ProcessLotJob do
      2.times { Lots::UploadService.new.call(uploaded_file, uploader: @user) }
    end
    assert_equal 2, @user.lots.count
    assert_equal [ "pending" ], @user.lots.distinct.pluck(:status)
    assert_equal 1, @user.lots.distinct.pluck(:checksum).size
  end

  test "limite 10 MB validado antes de persistir qualquer registro ou blob" do
    upload = uploaded_file("x" * (10.megabytes + 1))
    assert_no_difference [ "Lot.count", "ActiveStorage::Blob.count" ] do
      assert_raises(Lots::UploadService::InvalidUpload) { Lots::UploadService.new.call(upload, uploader: @user) }
    end
    accepted = Lots::UploadService.new.call(uploaded_file("x" * 10.megabytes), uploader: @user)
    assert_equal 10.megabytes, accepted.byte_size
  end

  test "não confia no MIME informado e higieniza nomes" do
    lot = Lots::UploadService.new.call(uploaded_file(pdf_document, name: "../../exemplo.pdf", mime: "text/html"), uploader: @user)
    assert_equal "exemplo.pdf", lot.name
    assert_equal "application/pdf", lot.content_type
  end
  test "arquivo original já está armazenado quando job é enfileirado" do
    callback = ->(id) do
      lot = Lot.find(id)
      assert lot.file.blob.service.exist?(lot.file.blob.key)
      assert_equal "capacitação".b, lot.file.download
    end
    ProcessLotJob.stub(:perform_later, callback) do
      Lots::UploadService.new.call(uploaded_file("capacitação"), uploader: @user)
    end
  end
end
