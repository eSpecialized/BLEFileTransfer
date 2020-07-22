//
//  ImageDisplayViewController.swift
//  CoreBluetoothLESample
//
//  Created by William Thompson on 7/21/20.
//  Copyright © 2020 Apple. All rights reserved.
//

import UIKit

class ImageDisplayViewController: UIViewController {

    var image: UIImage? {
        didSet {
            addNewFadeOld(image: image)
        }
    }

    @IBOutlet weak var imageView: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()

        imageView.image = image
    }

    func addNewFadeOld(image: UIImage?) {
        guard imageView != nil, let image = image else { return }

        let newImageView = UIImageView(image: image)
        let originalImageView = imageView

        newImageView.alpha = 0
        newImageView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(newImageView)

        //constrain it
        view.addConstraints([
            newImageView.topAnchor.constraint(equalTo: view.topAnchor),
            newImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            newImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            newImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        UIView.animate(
            withDuration: 0.5,
            animations: {
                newImageView.alpha = 1.0
            })
            { completed in
                originalImageView?.removeFromSuperview()
                self.imageView = newImageView
            }
    }
}
