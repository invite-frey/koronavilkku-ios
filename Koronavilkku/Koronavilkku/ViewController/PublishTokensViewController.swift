import Foundation
import UIKit
import SnapKit
import Combine
import ExposureNotification

class PublishTokensViewController: UIViewController {
    enum Text : String, Localizable {
        case Title
        case ButtonSubmit
        case AdditionalText
        case ErrorWrongPublishToken
        case ErrorNetwork
        case FinishedTitle
        case FinishedText
        case FinishedButton
    }
    
    private let scrollView = UIScrollView()
    private lazy var button = RoundedButton(title: Text.ButtonSubmit.localized,
                                            action: { [weak self] in self?.sendPressed() })
    private let tokenCodeField = UITextField()
    private var errorView: UIView!
    private var errorLabel: UILabel!
    private var helperLabel = UILabel()
    private var progressIndicator = UIActivityIndicatorView(style: .large)
    
    private var failure: NSError? = nil {
        didSet {
            progressIndicator.stopAnimating()
            progressIndicator.isHidden = true
            
            button.isEnabled = true
            button.isUserInteractionEnabled = true
            
            updateErrorView(with: failure)
        }
    }
    
    let exposureRepository = Environment.default.exposureRepository
    var tasks = [AnyCancellable]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addKeyboardDisposer()
        
        navigationItem.title = Text.Title.localized
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Translation.ButtonCancel.localized, style: .plain, target: self, action: #selector(close))
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "arrow-left"), style: .plain, target: self, action: #selector(close))
        navigationItem.leftBarButtonItem?.accessibilityLabel = Translation.ButtonBack.localized

        initUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.largeTitleDisplayMode = .never
        
        if tokenCodeField.text?.isEmpty == true {
            // No code was provided (not opened via link) -> show keyboard.
            tokenCodeField.becomeFirstResponder()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationItem.largeTitleDisplayMode = .automatic
    }
    
    @objc
    func close() {
        self.dismiss(animated: true, completion: nil)
    }
    
    func initUI() {
        view.addSubview(scrollView)
        
        scrollView.isUserInteractionEnabled = true
        
        scrollView.backgroundColor = UIColor.Secondary.blueBackdrop
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        let wrapper = UIView()
        scrollView.addSubview(wrapper)
        wrapper.snp.makeConstraints { make in
            make.width.equalTo(view)
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
        }
        
        wrapper.isUserInteractionEnabled = true

        errorView = createErrorView()
        errorView.isHidden = true
        wrapper.addSubview(errorView)
        errorView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.left.right.equalToSuperview().inset(20)
        }
                                
        tokenCodeField.backgroundColor = UIColor.Greyscale.white
        tokenCodeField.layer.shadowColor = .dropShadow
        tokenCodeField.layer.shadowOpacity = 1
        tokenCodeField.layer.shadowOffset = CGSize(width: 0, height: 4)
        tokenCodeField.layer.shadowRadius = 14
        tokenCodeField.font = UIFont.coronaCode
        tokenCodeField.layer.cornerRadius = 8
        tokenCodeField.textAlignment = .center
        tokenCodeField.keyboardType = .asciiCapableNumberPad
        tokenCodeField.autocorrectionType = .no
        tokenCodeField.delegate = self
        tokenCodeField.accessibilityLabel = Text.Title.localized
        tokenCodeField.addTarget(self, action: #selector(updateButtonEnabled), for: .editingChanged)

        updateButtonEnabled()

        wrapper.addSubview(tokenCodeField)
        tokenCodeField.snp.makeConstraints { make in
            make.top.equalTo(errorView.snp.bottom).offset(20)
            make.left.right.equalTo(view).inset(20)
            make.height.equalTo(63)
        }

        wrapper.addSubview(progressIndicator)
        progressIndicator.isHidden = true
        progressIndicator.snp.makeConstraints { make in
            make.centerY.equalTo(errorView.snp.centerY)
            make.left.right.equalTo(view).inset(20)
            make.height.equalTo(40)
        }

        wrapper.addSubview(button)
        button.snp.makeConstraints { make in
            make.top.equalTo(tokenCodeField.snp.bottom).offset(40)
            make.left.right.equalToSuperview().inset(20)
        }
        
        let infoLabel = createInfoLabel()
        infoLabel.numberOfLines = 0
        wrapper.addSubview(infoLabel)
        infoLabel.snp.makeConstraints { make in
            make.top.equalTo(button.snp.bottom).offset(20)
            make.left.right.equalToSuperview().inset(20)
            make.bottom.equalToSuperview()
        }
    }
    
    func setCode(_ code: String) {
        tokenCodeField.text = code
        updateButtonEnabled()
    }
            
    private func createInfoLabel() -> UILabel {
        let label = UILabel(label: Text.AdditionalText.localized,
                       font: UIFont.bodySmall,
                       color: UIColor.Greyscale.black)
        label.textAlignment = .center
        return label
    }
    
    private func createErrorView() -> UIView {
        let wrapper = UIView()
        
        let image = UIImageView(image: UIImage(named: "alert-octagon")!.withTintColor(UIColor.Primary.red))
        image.contentMode = .scaleAspectFit
        wrapper.addSubview(image)
        image.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalTo(22)
        }
        
        errorLabel = UILabel(label: Text.ErrorWrongPublishToken.localized,
                       font: UIFont.heading5,
                       color: UIColor.Primary.red)
        errorLabel.numberOfLines = 0
        errorLabel.lineBreakMode = .byWordWrapping
        wrapper.addSubview(errorLabel)
        errorLabel.snp.makeConstraints { make in
            make.left.equalTo(image.snp.right).offset(14)
            make.top.equalTo(image)
            make.right.bottom.equalToSuperview()
        }
        
        return wrapper
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true)
    }
    
    @objc func sendPressed() {
        DispatchQueue.main.async {
            self.errorView.isHidden = true
            self.progressIndicator.startAnimating()
            self.button.isEnabled = false
            self.button.isUserInteractionEnabled = false
        }
        exposureRepository.postExposureKeys(publishToken: tokenCodeField.text ?? nil)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: {
                    switch $0 {
                    case .failure(let error as NSError):
                        Log.e("Failed to post exposure keys: \(error)")
                        self.failure = error

                    case .finished:
                        self.showFinishViewController()
                    }
                },
                receiveValue: {}
            )
            .store(in: &tasks)
    }
    
    func showFinishViewController() {
        let finishViewController = InfoViewController()
        finishViewController.image = UIImage(named: "ok")
        finishViewController.titleText = Text.FinishedTitle.localized
        finishViewController.textLabelText = Text.FinishedText.localized
        finishViewController.buttonTitle = Text.FinishedButton.localized
        finishViewController.buttonPressed = {
            UIApplication.shared.selectRootTab(.home)
            finishViewController.dismiss(animated: true, completion: nil)
        }
        
        self.show(finishViewController, sender: self.parent)
    }
    
    private func updateErrorView(with failure: NSError?) {
        
        if let failure = failure {
            errorView.isHidden = false
            
            if failure.equals(.notAuthorized) {
                errorView.isHidden = true
            } else if failure.domain == NSURLErrorDomain {
                errorLabel.text = Text.ErrorNetwork.localized
            } else if failure.domain == KVRestErrorDomain {
                errorLabel.text = Text.ErrorWrongPublishToken.localized
            } else {
                errorLabel.text = "\(Text.ErrorWrongPublishToken.localized) (\(failure.code))"
            }
            
            if !errorView.isHidden {
                UIAccessibility.post(notification: .screenChanged, argument: errorLabel)
            }
            
        } else {
            errorView.isHidden = true
        }

        // Don't show the error text if user didn't grant permission to use keys (as it would be misleading).
        errorView.isHidden = failure == nil || failure!.equals(.notAuthorized)
    }
    
    @objc private func updateButtonEnabled() {
        let invalid = tokenCodeField.text?.isEmpty == true
        button.setEnabled(!invalid)
    }
}

extension NSError {
    func equals(_ code: ENError.Code) -> Bool {
        return domain == ENErrorDomain && self.code == code.rawValue
    }
}

extension PublishTokensViewController: UITextFieldDelegate {
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        let oldLength = textField.text?.count ?? 0
        let replacementLength = string.count
        let rangeLength = range.length
        
        let newLength = oldLength - rangeLength + replacementLength
        
        let returnPressed = string.range(of: "\n") != nil
        
        return newLength <= 12 || returnPressed
    }
}

#if DEBUG
import SwiftUI

struct InsertCoronaCodeViewControllerPreview: PreviewProvider {
    static var previews: some View = createPreview(for: UINavigationController(rootViewController: PublishTokensViewController()))
}
#endif
