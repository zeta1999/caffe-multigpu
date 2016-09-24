#include <vector>
#include <utility>
#include <math.h>

#include "caffe/layers/semi_hinge_loss_layer.hpp"

namespace caffe{
	template <typename Dtype>
	void SemiHingeLossLayer<Dtype>::Forward_gpu(const vector<Blob<Dtype>*>& bottom,
		const vector<Blob<Dtype>*>& top){
		const int count = bottom[0]->count();
		const int dim = bottom[0]->count(axis_);
		const int num = count / dim;
		const Dtype* x1_data = bottom[0]->gpu_data();
		const Dtype* x2_data = bottom[0]->gpu_data();
		Dtype* diff_data = diff_->mutable_gpu_data();
		caffe_gpu_sub(count, x1_data, x2_data, diff_data);
		const Dtype* label_1 = bottom[2]->cpu_data();
		const Dtype* label_2 = bottom[3]->cpu_data();
		// distance
		Dtype* dist_data = dist_->mutable_cpu_data();
		for (int n = 0; n < num; ++n){
			int label_1 = static_cast<int>(label_1[n]);
			int label_2 = static_cast<int>(label_2[n]);
			// D(x_1, x_2)
			Dtype dist;
			caffe_gpu_dot(dim, diff_data, diff_data, &dist);
			if (label_1 != ignore_label_ && label_2 != ignore_label_){
				// indicator
				int ind = label_1 == label_2 ? 1 : -1;
				// supervised hinge loss
				dist_data[n] = std::max(0, sup_bias_ - ind * (sup_thre_ - dist));
				loss += dist_data[n];
			}
			else{
				// unsupervised hinge loss
				dist_data[n] = gamma_ * std::max(0, unsup_bias_ - abs(unsup_thre_ - dist));
				loss += dist_data[n];
			}
			diff_data += dim;
		}
		top[0]->mutable_cpu_data()[0] = loss / num;
	}

	template <typename Dtype>
	void SemiHingeLossLayer<Dtype>::Backward_gpu(const vector<Blob<Dtype>*>& top,
		const vector<bool>& propagate_down,
		const vector<Blob<Dtype>*>& bottom){
		const int num = bottom[0]->count(0, axis_);
		const int dim = bottom[0]->count(axis_);
		Dtype* bottom_diff_1 = bottom[0]->mutable_gpu_diff();
		Dtype* bottom_diff_2 = bottom[1]->mutable_gpu_diff();
		const Dtype* label_1 = bottom[2]->cpu_data();
		const Dtype* label_2 = bottom[3]->cpu_data();
		const Dtype* diff_data = diff_->gpu_data();
		const Dtype* dist_data = dist_->cpu_data();
		Dtype loss_weight = top[0]->cpu_diff()[0];
		for (int n = 0; n < num; ++n){
			int label_1 = static_cast<int>(label_1[n]);
			int label_2 = static_cast<int>(label_2[n]);
			if (label_1 != ignore_label_ && label_2 != ignore_label_){
				// indicator 
				int ind = label_1 == label_2 ? 1 : -1;
				// supervised
				if (dist[n] > 0){
					if (propagate_down[0]){
						caffe_gpu_axpby(dim, Dtype(ind * loss_weight / num * 2), diff_data,
							Dtype(0), bottom_diff_1);
					}
					if (propagate_down[1]){
						caffe_gpu_axpby(dim, Dtype(-ind * loss_weight / num * 2), diff_data,
							Dtype(0), bottom_diff_2);
					}
				}
			}
			else{
				// unsupervised
				if (dist[n] > 0){
					if (propagate_down[0]){
						caffe_gpu_axpby(dim, Dtype(gamma_ * loss_weight / num * 2), diff_data,
							Dtype(0), bottom_diff_1);
					}
					if (propagate_down[1]){
						caffe_gpu_axpby(dim, Dtype(-gamma_ * loss_weight / num * 2), diff_data,
							Dtype(0), bottom_diff_2);
					}
				}
			}
			diff_data += dim;
			bottom_diff_1 += dim;
			bottom_diff_2 += dim;
		}
	}

	INSTANTIATE_LAYER_GPU_FUNCS(SemiHingeLossLayer);

} // namespace caffe