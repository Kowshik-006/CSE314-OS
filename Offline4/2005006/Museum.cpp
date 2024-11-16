#include<iostream>
#include<pthread.h>
#include<semaphore.h>
#include<unistd.h>
#include <ctime>
#include<random>

#define GALLERY1_CAPACITY 100
#define GLASS_CORRIDOR_CAPACITY 3

using namespace std;

// Semaphores for exclusive access to each step
sem_t step1, step2, step3;
sem_t gallery1,glass_corridor;
sem_t photo_booth;
sem_t count_lock;
sem_t print_lock;
sem_t priority_lock;
sem_t premium_count_lock;

int standard_visitors,premium_visitors;
int hallway_time, gallery1_time, gallery2_time, photo_booth_time;
time_t start_time;
int std_visitor_in_pbooth = 0;
int prm_visitor_in_pbooth = 0;

void init_time(){
    start_time = time(nullptr);
}

int get_time(){
    return time(nullptr) - start_time;
}

void init_semaphores(){
    sem_init(&step1,0,1);
    sem_init(&step2,0,1);
    sem_init(&step3,0,1);
    sem_init(&gallery1,0,GALLERY1_CAPACITY);
    sem_init(&glass_corridor,0,GLASS_CORRIDOR_CAPACITY);
    sem_init(&photo_booth,0,1);
    sem_init(&count_lock,0,1);
    sem_init(&print_lock,0,1);
    sem_init(&priority_lock,0,1);
    sem_init(&premium_count_lock,0,1);
}

class visitor{
    public:
        int id;
        bool selected;
        visitor(int id){
            this->id = id;
            this->selected = false;
        }
};

int get_random_number(int min, int max) {
  // Creates a random device for non-deterministic random number generation
  random_device rd;
  // Initializes a random number generator using the random device
  mt19937 generator(rd());

  // Lambda value for the Poisson distribution
  double lambda = 10000.234;

  // Defines a Poisson distribution with the given lambda
  poisson_distribution<int> poissonDist(lambda);

  // Generates a random number based on the Poisson distribution
  int rand = poissonDist(generator);
  // Returns a random number within the given range(inclusive) 
  return min + (rand % (max - min + 1));
}

void print(string msg){
    sem_wait(&print_lock);
    cout<<msg<<endl;
    sem_post(&print_lock);
}

void* visitor_thread_routine(void* arg){
    visitor* v = (visitor*)arg;
    //Enter hallway
    print("Visitor "+to_string(v->id)+" has arrived at A at timestamp "+to_string(get_time()));
    sleep(hallway_time);
    
    //Exit hallway
    print("Visitor "+to_string(v->id)+" has arrived at B at timestamp "+to_string(get_time()));
    sleep(1);
    
    //Take step 1
    sem_wait(&step1);  // exculsive access to step 1
    print("Visitor "+to_string(v->id)+" is at step 1 at timestamp "+to_string(get_time()));
    sleep(1);
    
    //Take step 2
    sem_wait(&step2);   // exclusive access to step 2
    print("Visitor "+to_string(v->id)+" is at step 2 at timestamp "+to_string(get_time()));
    sem_post(&step1);   // taken step 2, releasing step 1
    sleep(1);
    
    //Take step 3
    sem_wait(&step3);  // exclusive access to step 3
    print("Visitor "+to_string(v->id)+" is at step 3 at timestamp "+to_string(get_time()));
    sem_post(&step2);  // taken step 3, releasing step 2
    sleep(1);
    
    //Enter Gallery 1
    sem_wait(&gallery1);
    print("Visitor "+to_string(v->id)+" is at C (entered Gallery 1) at timestamp "+to_string(get_time()));
    // cout<<"Visitor "<<v->id<<" is at C (entered Gallery 1) at timestamp "<<get_time()<<endl;
    sem_post(&step3);  // entered gallery 1, releasing step 3
    sleep(gallery1_time);
    
    //Exit Gallery 1
    sem_wait(&glass_corridor);
    print("Visitor "+to_string(v->id)+" is at D (exiting Gallery 1) at timestamp "+to_string(get_time()));
    sem_post(&gallery1); // entered glass corridor, releasing gallery 1
    sleep(2);
    
    //Enter Gallery 2
    print("Visitor "+to_string(v->id)+" is at E (entered Gallery 2) at timestamp "+to_string(get_time()));
    sem_post(&glass_corridor); // entered gallery 2, releasing glass corridor
    sleep(gallery2_time);
    print("Visitor "+to_string(v->id)+" is about to enter the photo booth at timestamp "+to_string(get_time()));
    
    //Enter Photobooth
    
    //Premium visitor
    if(v->id>=2001 && v->id<=2100){
        sem_wait(&premium_count_lock);
        prm_visitor_in_pbooth++;
        if(prm_visitor_in_pbooth == 1) sem_wait(&priority_lock);
        sem_post(&premium_count_lock);
        
        // Excluisive access to photo booth
        sem_wait(&photo_booth);
        print("Visitor "+to_string(v->id)+" is inside the photo booth at timestamp "+to_string(get_time()));
        sleep(photo_booth_time);
        
        sem_wait(&premium_count_lock);
        prm_visitor_in_pbooth--;
        if(prm_visitor_in_pbooth == 0) sem_post(&priority_lock);
        sem_post(&premium_count_lock);
        
        sem_post(&photo_booth);
    }
    
    // Standard visitor 
    else if(v->id>=1001 && v->id<=1100){
        sleep(2);
        sem_wait(&priority_lock);
        //Enter photobooth
        sem_wait(&count_lock);
        std_visitor_in_pbooth++;
        //The first standard visitor to enter the photobooth will lock the photobooth
        if(std_visitor_in_pbooth == 1) sem_wait(&photo_booth);
        print("Visitor "+to_string(v->id)+" is inside the photo booth at timestamp "+to_string(get_time()));
        sem_post(&count_lock);
        
        sleep(photo_booth_time);
        
        sem_post(&priority_lock);
        sem_wait(&count_lock);
        std_visitor_in_pbooth--;
        //The last standard visitor to exit the photobooth will unlock the photobooth
        if(std_visitor_in_pbooth == 0) sem_post(&photo_booth);
        sem_post(&count_lock);
    }

    pthread_exit(NULL);
}

int main(int argc, char* argv[]){
    //Input
    // cin>>standard_visitors>>premium_visitors>>hallway_time>>gallery1_time>>gallery2_time>>photo_booth_time;
    if(argc != 7){
        cout<<"Invalid number of arguments"<<endl;
        exit(1);
    }
    standard_visitors = stoi(argv[1]);
    premium_visitors = stoi(argv[2]);
    hallway_time = stoi(argv[3]);
    gallery1_time = stoi(argv[4]);
    gallery2_time = stoi(argv[5]);
    photo_booth_time = stoi(argv[6]);
    
    init_semaphores();
    
    pthread_t visitor_threads[standard_visitors+premium_visitors];
    visitor** visitors = new visitor*[standard_visitors+premium_visitors]; 
    

    for(int i=0;i<standard_visitors+premium_visitors;i++){
        visitors[i] = new visitor(i+1+1000);
    }

    for(int i=0;i<premium_visitors;i++){
        visitors[standard_visitors + i] = new visitor(i+1+2000);
    }
    
    init_time();

    int visitorsToEnter =  standard_visitors+premium_visitors;
    while(visitorsToEnter > 0){
        int selected_visitor = get_random_number(0,standard_visitors+premium_visitors-1);
        if(!visitors[selected_visitor]->selected){
            visitors[selected_visitor]->selected = true;
            pthread_create(&visitor_threads[selected_visitor],NULL,visitor_thread_routine,(void*)visitors[selected_visitor]);
            visitorsToEnter--;
            sleep(get_random_number(1,3));
        }
    }

    for(int i=0;i<standard_visitors+premium_visitors;i++){
        pthread_join(visitor_threads[i],NULL);
    }

    //Freeing memory
    for(int i=0;i<standard_visitors+premium_visitors;i++){
        delete visitors[i];
    }
    delete[] visitors;

    return 0;
}