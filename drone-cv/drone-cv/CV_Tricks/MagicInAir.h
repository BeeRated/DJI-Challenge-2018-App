//
//  MagicInAir.h
//  drone-cv
//
//  Created by Zhiyuan Li on 7/27/17.
//  Copyright © 2017 dji. All rights reserved.
//

#ifndef MagicInAir_h
#define MagicInAir_h

#ifdef __cplusplus
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/objdetect/objdetect.hpp>
#include <opencv2/core/core.hpp>
#include <list>

using namespace std;
using namespace cv;

void filterLaplace(Mat image, int kernel_size);
void filterBlurHomogeneousAccelerated(Mat image, int kernel_size);

class SimpleFaceDetector
{
private:
    cv::CascadeClassifier* face_cascade;
    void loadCascades(std::string filename);
public:
    SimpleFaceDetector(std::string filename);
    ~SimpleFaceDetector();
    int detectFaceInMat(cv::Mat &grayMat);
};
#endif

#endif /* MagicInAir_h */
